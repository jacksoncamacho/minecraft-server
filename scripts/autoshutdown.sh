#!/bin/bash
# autoshutdown.sh
# Checks if any players are online and shuts down the server if empty for 15 minutes.

CHECK_INTERVAL=300 # 5 minutes
IDLE_LIMIT=900    # 15 minutes (3 intervals)
IDLE_COUNT=0
MINECRAFT_DIR="/opt/minecraft"

while true; do
    # Check if minecraft is running
    if systemctl is-active --quiet minecraft; then
        # Use netstat to check for established connections on 25565
        PLAYER_COUNT=$(netstat -atn | grep :25565 | grep ESTABLISHED | wc -l)
        
        if [ "$PLAYER_COUNT" -eq 0 ]; then
            IDLE_COUNT=$((IDLE_COUNT + CHECK_INTERVAL))
            echo "No players online. Idle for $IDLE_COUNT seconds."
        else
            IDLE_COUNT=0
            echo "$PLAYER_COUNT players online. Resetting idle counter."
        fi

        if [ "$IDLE_COUNT" -ge "$IDLE_LIMIT" ]; then
            echo "Idle limit reached. Shutting down server..."
            # Take a final backup
            /usr/local/bin/minecraft-backup.sh
            # Shutdown the instance
            sudo shutdown -h now
            exit 0
        fi
    fi
    sleep $CHECK_INTERVAL
done
