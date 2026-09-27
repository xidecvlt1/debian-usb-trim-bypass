#!/bin/bash

# Ensure script is executed as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script as root (sudo ./bypass-trim-install.sh)"
  exit 1
fi

TARGET_SCRIPT="/usr/local/bin/trim-bypass.sh"
OVERRIDE_DIR="/etc/systemd/system/fstrim.service.d"

# Uninstall Function
do_uninstall() {
    echo "=========================================="
    echo "       TRIM BYPASS UNINSTALLATION         "
    echo "=========================================="
    
    # 1. Remove systemd fstrim override
    if [ -d "$OVERRIDE_DIR" ]; then
        echo "[1/3] Removing systemd fstrim override..."
        rm -rf "$OVERRIDE_DIR"
    fi

    # 2. Remove executable script
    if [ -f "$TARGET_SCRIPT" ]; then
        echo "[2/3] Removing script $TARGET_SCRIPT..."
        rm -f "$TARGET_SCRIPT"
    fi

    # 3. Reload systemd daemon to restore default behavior
    echo "[3/3] Restoring systemd default configuration..."
    systemctl daemon-reload
    
    echo "=========================================="
    echo "[+] Uninstallation completed successfully!"
    echo "    fstrim.service has been restored to default system behavior."
    echo "=========================================="
}

# Main Menu
echo "=========================================="
echo "    Bypass TRIM SSD - Installer / Manager "
echo "=========================================="
echo "1) Install / Re-install (Select new disk)"
echo "2) Uninstall (Restore to default)"
echo "3) Exit"
echo "=========================================="
read -p "Select an option [1-3]: " MENU_OPTION

case "$MENU_OPTION" in
    2)
        do_uninstall
        exit 0
        ;;
    3)
        echo "Cancelled."
        exit 0
        ;;
    1)
        # Proceed to installation/reinstallation
        ;;
    *)
        echo "[-] Invalid option."
        exit 1
        ;;
esac

# Clean up existing override configuration if re-installing
if [ -f "$TARGET_SCRIPT" ] || [ -d "$OVERRIDE_DIR" ]; then
    echo "[!] Cleaning up previous configuration..."
    rm -rf "$OVERRIDE_DIR" "$TARGET_SCRIPT"
fi

echo ""
echo "=========================================="
echo "          AVAILABLE DISK DRIVES           "
echo "=========================================="
lsblk -d -o NAME,SIZE,MODEL,ROTA,TRAN | grep -v "loop"
echo "=========================================="

# Prompt for target drive
read -p "Enter target drive name (e.g., sda, sdb): " TARGET_DRIVE

# Validate target block device
if [ ! -b "/dev/$TARGET_DRIVE" ]; then
    echo "[-] Error: Device /dev/$TARGET_DRIVE not found!"
    exit 1
fi

# Auto-detect mountpoint if already mounted
DETECTED_MOUNT=$(lsblk -no MOUNTPOINTS "/dev/$TARGET_DRIVE" | grep -v '^$' | head -n 1)
if [ -n "$DETECTED_MOUNT" ]; then
    read -p "Enter SSD mountpoint [Default: $DETECTED_MOUNT]: " TARGET_MOUNT
    TARGET_MOUNT=${TARGET_MOUNT:-$DETECTED_MOUNT}
else
    read -p "Enter SSD mountpoint (e.g., /media/ssd): " TARGET_MOUNT
fi

if [ -z "$TARGET_MOUNT" ]; then
    echo "[-] Error: Mountpoint cannot be empty!"
    exit 1
fi

echo ""
echo "[1/4] Generating $TARGET_SCRIPT for drive /dev/$TARGET_DRIVE (mount: $TARGET_MOUNT)..."
cat << EOF > "$TARGET_SCRIPT"
#!/bin/bash
# Force provisioning_mode to unmap for drive $TARGET_DRIVE
if [ -d "/sys/block/$TARGET_DRIVE/device/scsi_disk" ]; then
    echo "unmap" | tee /sys/block/$TARGET_DRIVE/device/scsi_disk/*/provisioning_mode > /dev/null
fi

# Execute TRIM
fstrim -v "$TARGET_MOUNT"

echo "Done! TRIM successfully bypassed for /dev/$TARGET_DRIVE at $TARGET_MOUNT."
EOF

# Grant execution permission
chmod +x "$TARGET_SCRIPT"

echo "[2/4] Setting up systemd fstrim.service override..."
mkdir -p "$OVERRIDE_DIR"
cat << 'EOF' > "$OVERRIDE_DIR/override.conf"
[Service]
ExecStart=
ExecStart=/usr/local/bin/trim-bypass.sh
PrivateDevices=no
PrivateNetwork=yes
PrivateUsers=no
# REQUIRED: Set to 'no' so the script can write to /sys/block/
ProtectKernelTunables=no
ProtectKernelModules=no
ProtectControlGroups=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@default @file-system @basic-io @system-service
EOF

echo "[3/4] Reloading systemd daemon and enabling fstrim.timer..."
systemctl daemon-reload
systemctl enable --now fstrim.timer

echo "[4/4] Setup complete! Testing fstrim.service execution..."
systemctl start fstrim.service

echo ""
echo "=== Last Execution Status ==="
systemctl status fstrim.service --no-pager
