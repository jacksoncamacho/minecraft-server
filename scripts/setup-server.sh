#!/bin/bash
set -e
# --- REBUILD TRIGGER: 2026-03-23T01:35:00 ---

# --- Configuration ---
MINECRAFT_DIRECTORY="/opt/minecraft"
S3_BUCKET="${s3_bucket}"
JAVA_VERSION="21"
FABRIC_LOADER_VERSION="0.17.2"
MINECRAFT_VERSION="1.21.10"

# --- Install Dependencies ---
apt-get update
apt-get install -y openjdk-$JAVA_VERSION-jre-headless wget curl git screen net-tools unzip

# Install AWS CLI v2
echo "STEP: Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/
/usr/local/bin/aws --version

# --- Setup Minecraft User ---
echo "STEP: Setting up minecraft user..."
if ! id -u minecraft >/dev/null 2>&1; then
  useradd -m -r -d $MINECRAFT_DIRECTORY minecraft
fi

mkdir -p $MINECRAFT_DIRECTORY/mods
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY

# --- Download Fabric Loader ---
echo "STEP: Downloading Fabric loader..."
INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar"
wget -O /tmp/fabric-installer.jar $INSTALLER_URL
echo "STEP: Running Fabric installer..."
sudo -u minecraft java -jar /tmp/fabric-installer.jar server -mcversion $MINECRAFT_VERSION -loader $FABRIC_LOADER_VERSION -dir $MINECRAFT_DIRECTORY -downloadMinecraft
ls -l $MINECRAFT_DIRECTORY/fabric-server-launch.jar

# --- EULA ---
echo "eula=true" > $MINECRAFT_DIRECTORY/eula.txt
chown minecraft:minecraft $MINECRAFT_DIRECTORY/eula.txt

# --- Server Properties ---
# Basic optimized settings
cat <<EOF > $MINECRAFT_DIRECTORY/server.properties
difficulty=normal
gamemode=survival
max-players=20
motd=Aplico lo que se a lo que mejor se hacer aparte de esto, amarte
view-distance=10
simulation-distance=8
server-port=25565
EOF
chown minecraft:minecraft $MINECRAFT_DIRECTORY/server.properties

# --- Mod Sync ---
mkdir -p $MINECRAFT_DIRECTORY/mods
/usr/local/bin/aws s3 sync s3://$S3_BUCKET/mods/ $MINECRAFT_DIRECTORY/mods/
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/mods

# --- Setup Backup Script (3-Version Rotation) ---
cat <<EOF > /usr/local/bin/minecraft-backup.sh
#!/bin/bash
S3_BUCKET="$S3_BUCKET"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
echo "[$(date)] Starting versioned backup to s3://\$S3_BUCKET/backups/\$TIMESTAMP/"

# 1. Force a save-all
sudo -u minecraft screen -S minecraft -X eval 'stuff "save-all\\015"'
sleep 5

# 2. Sync to a NEW timestamped folder
/usr/local/bin/aws s3 sync /opt/minecraft/world/ s3://\$S3_BUCKET/backups/\$TIMESTAMP/

# 3. Cleanup: Keep only the 3 most recent snapshots
echo "Cleaning up old backups..."
# List prefixes, sort by date desc, skip top 3, delete the rest
/usr/local/bin/aws s3 ls s3://\$S3_BUCKET/backups/ | grep "PRE " | awk '{print \$2}' | sort -r | tail -n +4 | while read -r line; do
    echo "Deleting old backup: \$line"
    /usr/local/bin/aws s3 rm s3://\$S3_BUCKET/backups/\$line --recursive
done

echo "[$(date)] Backup complete."
EOF
chmod +x /usr/local/bin/minecraft-backup.sh
(crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/minecraft-backup.sh >> /var/log/minecraft-backup.log 2>&1") | crontab -

# --- Restore World from S3 (Latest Snapshot) ---
echo "Checking for versioned backups in S3..."
LATEST_BACKUP=$(/usr/local/bin/aws s3 ls s3://$S3_BUCKET/backups/ | grep "PRE " | awk '{print $2}' | sort -r | head -n 1)

if [ -n "$LATEST_BACKUP" ]; then
    echo "Restoring latest backup: $LATEST_BACKUP"
    /usr/local/bin/aws s3 sync s3://$S3_BUCKET/backups/$LATEST_BACKUP $MINECRAFT_DIRECTORY/world/
    chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/world/
else
    echo "No versioned backups found. Checking for legacy 'world/' folder..."
    /usr/local/bin/aws s3 sync s3://$S3_BUCKET/world/ $MINECRAFT_DIRECTORY/world/
    chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/world/
fi

# --- Setup Systemd Service ---
echo "STEP: Creating systemd service..."
cat <<EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=minecraft
WorkingDirectory=$MINECRAFT_DIRECTORY
Environment="TERM=xterm-256color"
# Running inside a screen session allows interactive console access
ExecStart=/usr/bin/screen -DmS minecraft /usr/bin/java -Xms1G -Xmx1536M -XX:+UseG1GC -jar fabric-server-launch.jar nogui
# Graceful shutdown by sending "stop" to the screen session
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff "stop\\015"'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "STEP: Starting services..."
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

echo "============================================"
echo " SETUP COMPLETE - SERVER IS STARTING "
echo "============================================"
