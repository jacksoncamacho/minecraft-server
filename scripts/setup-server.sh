#!/bin/bash
set -e

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
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# --- Setup Minecraft User ---
if ! id -u minecraft >/dev/null 2>&1; then
  useradd -m -r -d $MINECRAFT_DIRECTORY minecraft
fi

mkdir -p $MINECRAFT_DIRECTORY/mods
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY

# --- Download Fabric Loader ---
# We use the official Fabric installer
INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar"
wget -O /tmp/fabric-installer.jar $INSTALLER_URL
sudo -u minecraft java -jar /tmp/fabric-installer.jar server -mcversion $MINECRAFT_VERSION -loader $FABRIC_LOADER_VERSION -dir $MINECRAFT_DIRECTORY -downloadMinecraft

# --- EULA ---
echo "eula=true" > $MINECRAFT_DIRECTORY/eula.txt
chown minecraft:minecraft $MINECRAFT_DIRECTORY/eula.txt

# --- Server Properties ---
# Basic optimized settings
cat <<EOF > $MINECRAFT_DIRECTORY/server.properties
difficulty=normal
gamemode=survival
max-players=20
motd=Minecraft Server on AWS
view-distance=10
simulation-distance=8
server-port=25565
EOF
chown minecraft:minecraft $MINECRAFT_DIRECTORY/server.properties

# --- Mod Sync ---
mkdir -p $MINECRAFT_DIRECTORY/mods
aws s3 sync s3://$S3_BUCKET/mods/ $MINECRAFT_DIRECTORY/mods/
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/mods

# --- Setup Backup Cron (10 Minutes) ---
cat <<EOF > /usr/local/bin/minecraft-backup.sh
#!/bin/bash
# Fixed path to be consistent with Restore phase
S3_BUCKET="$S3_BUCKET"
echo "[$(date)] Starting world backup to s3://\$S3_BUCKET/world/"
# Force a save-all if the server is running (via screen)
# We send the command to the screen session as the minecraft user
sudo -u minecraft screen -S minecraft -X eval 'stuff "save-all\\015"'
sleep 5
/usr/local/bin/aws s3 sync /opt/minecraft/world/ s3://\$S3_BUCKET/world/ --delete
echo "[$(date)] Backup complete."
EOF
chmod +x /usr/local/bin/minecraft-backup.sh
(crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/minecraft-backup.sh >> /var/log/minecraft-backup.log 2>&1") | crontab -

# --- Setup Auto-Shutdown ---
cat <<EOF > /usr/local/bin/autoshutdown.sh
#!/bin/bash
CHECK_INTERVAL=300
IDLE_LIMIT=900
IDLE_COUNT=0
while true; do
    if systemctl is-active --quiet minecraft; then
        PLAYER_COUNT=\$(netstat -atn | grep :25565 | grep ESTABLISHED | wc -l)
        if [ "\$PLAYER_COUNT" -eq 0 ]; then
            IDLE_COUNT=\$((\$IDLE_COUNT + \$CHECK_INTERVAL))
            echo "No players online. Idle for \$IDLE_COUNT seconds."
        else
            IDLE_COUNT=0
        fi
        if [ "\$IDLE_COUNT" -ge "\$IDLE_LIMIT" ]; then
            /usr/local/bin/minecraft-backup.sh
            sudo shutdown -h now
            exit 0
        fi
    fi
    sleep \$CHECK_INTERVAL
done
EOF
chmod +x /usr/local/bin/autoshutdown.sh
cat <<EOF > /etc/systemd/system/autoshutdown.service
[Unit]
Description=Minecraft Auto-Shutdown
After=minecraft.service

[Service]
ExecStart=/usr/local/bin/autoshutdown.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable autoshutdown

# --- Restore World from S3 ---
echo "Checking for world backups in S3..."
aws s3 sync s3://$S3_BUCKET/world/ $MINECRAFT_DIRECTORY/world/
chown -R minecraft:minecraft $MINECRAFT_DIRECTORY/world/

# --- Setup Systemd Service ---
cat <<EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=minecraft
WorkingDirectory=$MINECRAFT_DIRECTORY
# Running inside a screen session allows interactive console access
ExecStart=/usr/bin/screen -DmS minecraft /usr/bin/java -Xms1G -Xmx1536M -XX:+UseG1GC -jar fabric-server-launch.jar nogui
# Graceful shutdown by sending "stop" to the screen session
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff "stop\\015"'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minecraft
# We don't start it yet as we need to sync mods via the pipeline/script
