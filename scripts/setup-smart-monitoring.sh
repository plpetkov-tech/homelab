#!/bin/bash

# Setup SMART monitoring on Proxmox host for early disk failure detection

set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-10.11.12.136}"
ALERT_EMAIL="${ALERT_EMAIL:-root@localhost}"

echo "🔧 Setting up SMART monitoring on Proxmox host..."

# Install smartmontools if not present
ssh root@"$PROXMOX_HOST" "apt-get update && apt-get install -y smartmontools mailutils"

# Create smartd configuration
cat << 'EOF' | ssh root@"$PROXMOX_HOST" "cat > /etc/smartd.conf"
# smartd configuration for ClusterCreator gamma datastore monitoring

# Monitor all gamma datastore SSDs
/dev/sda -a -o on -S on -s (S/../.././02|L/../../6/03) -m root@localhost -M exec /usr/local/bin/smart-alert.sh
/dev/sdc -a -o on -S on -s (S/../.././02|L/../../6/03) -m root@localhost -M exec /usr/local/bin/smart-alert.sh  
/dev/sdd -a -o on -S on -s (S/../.././02|L/../../6/03) -m root@localhost -M exec /usr/local/bin/smart-alert.sh
/dev/sde -a -o on -S on -s (S/../.././02|L/../../6/03) -m root@localhost -M exec /usr/local/bin/smart-alert.sh

# Configuration explanation:
# -a: Monitor all attributes
# -o on: Enable automatic offline data collection
# -S on: Enable attribute autosave
# -s: Schedule self-tests (short daily at 2AM, long weekly on Saturday at 3AM)
# -m: Email address for alerts
# -M exec: Execute custom script for alerts
EOF

# Create custom alert script
cat << 'EOF' | ssh root@"$PROXMOX_HOST" "cat > /usr/local/bin/smart-alert.sh"
#!/bin/bash

# Custom SMART alert script for ClusterCreator
# This script is called by smartd when disk issues are detected

DEVICE="$1"
MESSAGE="$2"
ALERT_EMAIL="${ALERT_EMAIL:-root@localhost}"

# Log the alert
logger -t smartd "DISK ALERT: $DEVICE - $MESSAGE"

# Send email with detailed SMART info
{
    echo "ClusterCreator Disk Alert"
    echo "========================="
    echo "Device: $DEVICE"
    echo "Alert: $MESSAGE"
    echo "Time: $(date)"
    echo
    echo "Current SMART Status:"
    smartctl -a "$DEVICE" || echo "Failed to get SMART data"
    echo
    echo "Recent kernel messages:"
    dmesg | grep "$(basename "$DEVICE")" | tail -10 || echo "No recent kernel messages"
} | mail -s "ClusterCreator: SMART Alert for $DEVICE" "$ALERT_EMAIL"

# If Telegram is configured, send notification
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="🚨 ClusterCreator SMART Alert: $DEVICE - $MESSAGE" >/dev/null 2>&1 || true
fi

# Additional actions based on alert type
case "$MESSAGE" in
    *"Temperature"*)
        echo "Temperature alert - consider checking cooling"
        ;;
    *"Reallocated"*|*"Pending"*)
        echo "Bad sector alert - disk may be failing"
        ;;
    *"Wear"*|*"Life"*)
        echo "Wear level alert - SSD approaching end of life"
        ;;
esac
EOF

# Make alert script executable
ssh root@"$PROXMOX_HOST" "chmod +x /usr/local/bin/smart-alert.sh"

# Enable and start smartd service
ssh root@"$PROXMOX_HOST" "systemctl enable smartd && systemctl restart smartd"

# Create systemd service for our disk health monitor
cat << 'EOF' | ssh root@"$PROXMOX_HOST" "cat > /etc/systemd/system/clustercreator-disk-monitor.service"
[Unit]
Description=ClusterCreator Disk Health Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/clustercreator-disk-health-monitor.sh
User=root
Environment=PROXMOX_HOST=localhost

[Install]
WantedBy=multi-user.target
EOF

# Create timer for regular monitoring
cat << 'EOF' | ssh root@"$PROXMOX_HOST" "cat > /etc/systemd/system/clustercreator-disk-monitor.timer"
[Unit]
Description=Run ClusterCreator Disk Health Monitor every hour
Requires=clustercreator-disk-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Copy our monitoring script to Proxmox host
scp /home/plamen/ClusterCreator/scripts/disk-health-monitor.sh root@"$PROXMOX_HOST":/usr/local/bin/clustercreator-disk-health-monitor.sh
ssh root@"$PROXMOX_HOST" "chmod +x /usr/local/bin/clustercreator-disk-health-monitor.sh"

# Enable the timer
ssh root@"$PROXMOX_HOST" "systemctl daemon-reload && systemctl enable clustercreator-disk-monitor.timer && systemctl start clustercreator-disk-monitor.timer"

echo "✅ SMART monitoring setup complete!"
echo
echo "Configuration:"
echo "- smartd is monitoring /dev/sda, /dev/sdc, /dev/sdd, /dev/sde"
echo "- Self-tests run daily (short) and weekly (long)"
echo "- Custom health monitor runs every hour"
echo "- Alerts sent to: $ALERT_EMAIL"
echo
echo "To check status:"
echo "  ssh root@$PROXMOX_HOST 'systemctl status smartd'"
echo "  ssh root@$PROXMOX_HOST 'systemctl status clustercreator-disk-monitor.timer'"
echo
echo "To run manual health check:"
echo "  ./scripts/disk-health-monitor.sh"
echo
echo "To view SMART data manually:"
echo "  ssh root@$PROXMOX_HOST 'smartctl -a /dev/sda'"