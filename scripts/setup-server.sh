#!/bin/bash
set -e
# --- REBUILD TRIGGER (t4g.small + inline helper scripts fix): 2026-03-29T22:20:00 ---

# --- Configuration ---
MINECRAFT_DIRECTORY="/opt/minecraft"
S3_BUCKET="${s3_bucket}"
JAVA_VERSION="21"
FABRIC_LOADER_VERSION="0.18.4"
MINECRAFT_VERSION="1.21.11"

# Write env file so backup-s3.sh can read the bucket name at runtime
mkdir -p $MINECRAFT_DIRECTORY
echo "S3_BUCKET=$S3_BUCKET" > $MINECRAFT_DIRECTORY/.env

# --- Install Dependencies ---
apt-get update
apt-get install -y openjdk-$JAVA_VERSION-jre-headless wget curl git screen net-tools unzip

# Install AWS CLI v2
echo "STEP: Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
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

# --- Mod Sync (--size-only to avoid re-uploading unchanged jars) ---
echo "STEP: Syncing mods from S3..."
mkdir -p $MINECRAFT_DIRECTORY/mods
/usr/local/bin/aws s3 sync s3://$S3_BUCKET/mods/ $MINECRAFT_DIRECTORY/mods/ --size-only
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/mods

# --- Install backup script ---
echo "STEP: Installing backup script..."
cat <<'SCRIPT_EOF' > /usr/local/bin/minecraft-backup.sh
${backup_script}
SCRIPT_EOF
chmod +x /usr/local/bin/minecraft-backup.sh

# --- Restore World from S3 (Latest Snapshot) ---
echo "STEP: Restoring world from S3..."
LATEST_BACKUP=$(/usr/local/bin/aws s3 ls s3://$S3_BUCKET/backups/ | grep "PRE " | awk '{print $2}' | sort -r | head -n 1)

if [ -n "$LATEST_BACKUP" ] && [ "$LATEST_BACKUP" != "latest/" ] && [ "$LATEST_BACKUP" != "daily/" ]; then
    echo "Restoring from old versioned backup: $LATEST_BACKUP"
    /usr/local/bin/aws s3 sync s3://$S3_BUCKET/backups/$LATEST_BACKUP $MINECRAFT_DIRECTORY/world/
elif /usr/local/bin/aws s3 ls s3://$S3_BUCKET/backups/latest/ --summarize 2>/dev/null | grep -q "Total Objects"; then
    echo "Restoring from backups/latest/..."
    /usr/local/bin/aws s3 sync s3://$S3_BUCKET/backups/latest/ $MINECRAFT_DIRECTORY/world/ --size-only
else
    echo "No backup found. Starting fresh world."
fi
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/world/ 2>/dev/null || true

# --- Install autoshutdown script ---
echo "STEP: Installing autoshutdown script..."
cat <<'SCRIPT_EOF' > /usr/local/bin/autoshutdown.sh
${autoshutdown_script}
SCRIPT_EOF
chmod +x /usr/local/bin/autoshutdown.sh

# --- Setup Cron Jobs ---
# [1] Incremental world backup every 15 min (only changed chunks uploaded, --size-only --delete)
# [2] Daily S3-to-S3 snapshot at 3am (no EC2 bandwidth, pure S3 copy)
(crontab -l 2>/dev/null; cat <<'CRON'
*/15 * * * * /usr/local/bin/minecraft-backup.sh >> /var/log/minecraft-backup.log 2>&1
0 3 * * * /usr/local/bin/aws s3 sync s3://${s3_bucket}/backups/latest/ s3://${s3_bucket}/backups/daily/$(date +\%Y\%m\%d)/ --size-only >> /var/log/minecraft-backup.log 2>&1
CRON
) | crontab -

# --- Setup Systemd Service: Minecraft ---
echo "STEP: Creating systemd service..."
cat <<EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=minecraft
WorkingDirectory=$MINECRAFT_DIRECTORY
Environment="TERM=xterm-256color"
ExecStart=/usr/bin/screen -DmS minecraft /usr/bin/java -Xms1G -Xmx1536M -XX:+UseG1GC -jar fabric-server-launch.jar nogui
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff "stop\015"'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- Setup Systemd Service: Autoshutdown ---
cat <<EOF > /etc/systemd/system/autoshutdown.service
[Unit]
Description=Minecraft Auto-Shutdown (stops instance when empty for 15 min)
After=minecraft.service
Requires=minecraft.service

[Service]
ExecStart=/usr/local/bin/autoshutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "STEP: Starting services..."
systemctl daemon-reload
systemctl enable minecraft
systemctl enable autoshutdown
systemctl start minecraft
systemctl start autoshutdown

echo "============================================"
echo " SETUP COMPLETE - SERVER IS STARTING "
echo "============================================"
