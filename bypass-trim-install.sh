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
    echo "        TRIM BYPASS UNINSTALLATION        "
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
echo "1) Install / Re-install (Select Mount Point)"
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
echo "=========================================================================================="
echo "                                AVAILABLE STORAGE DRIVES                                  "
echo "=========================================================================================="

# Retrieve active mount point list (excluding boot, root, and virtual filesystems)
mapfile -t MOUNT_LIST < <(lsblk -ln -o MOUNTPOINTS | grep -E '^/' | grep -v -E '^/($|boot|boot/|sys|dev|run|proc)')

if [ ${#MOUNT_LIST[@]} -eq 0 ]; then
    echo "[-] No active user mount points found! Mount your SSD first."
    exit 1
fi

# Print Table Header with clean left-aligned column formatting
printf "%-4s %-8s %-8s %-35s %-20s\n" "NUM" "DEV" "SIZE" "MODEL" "MOUNT POINT"
echo "------------------------------------------------------------------------------------------"

# Display device data into table rows
for i in "${!MOUNT_LIST[@]}"; do
    # Find the partition name and its parent disk
    PART_DEV=$(df "${MOUNT_LIST[$i]}" | tail -1 | awk '{print $1}' | sed 's|/dev/||')
    PARENT_DEV=$(lsblk -no PKNAME "/dev/$PART_DEV" 2>/dev/null | xargs)
    [ -z "$PARENT_DEV" ] && PARENT_DEV=$(lsblk -no PKNAME "$(lsblk -lno PKNAME,MOUNTPOINTS | grep "${MOUNT_LIST[$i]}" | awk '{print $1}')" 2>/dev/null | xargs)
    
    # Retrieve size and model info EXCLUSIVELY from the parent disk specifically (-d / --nodeps)
    SIZE_INFO=$(lsblk -dno SIZE "/dev/$PARENT_DEV" 2>/dev/null | xargs)
    MODEL_INFO=$(lsblk -dno MODEL "/dev/$PARENT_DEV" 2>/dev/null | xargs)
    
    # If model name is empty, fill with default text
    [ -z "$MODEL_INFO" ] && MODEL_INFO="Generic Disk"

    # Print data row aligned with header columns without text duplication
    printf "%-4s %-8s %-8s %-35s %-20s\n" "$((i+1))" "$PARENT_DEV" "$SIZE_INFO" "${MODEL_INFO:0:33}" "${MOUNT_LIST[$i]}"
done
echo "=========================================================================================="

# Number-based selection prompt
read -p "Select target drive number [1-${#MOUNT_LIST[@]}]: " MOUNT_NUM

# Validate numeric input
if ! [[ "$MOUNT_NUM" =~ ^[0-9]+$ ]] || [ "$MOUNT_NUM" -lt 1 ] || [ "$MOUNT_NUM" -gt "${#MOUNT_LIST[@]}" ]; then
    echo "[-] Error: Invalid number selection!"
    exit 1
fi

TARGET_MOUNT="${MOUNT_LIST[$((MOUNT_NUM-1))]}"

echo ""
echo "[1/4] Generating $TARGET_SCRIPT for mount point: $TARGET_MOUNT..."
cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash
TARGET_MOUNT="REPLACE_WITH_MOUNT"

# 1. Dynamically detect device name (sda/sdb) based on the mount point
SSD_NAME=$(lsblk -no PKNAME "$(df "$TARGET_MOUNT" | tail -1 | awk '{print $1}')" 2>/dev/null || lsblk -no NAME -d | grep -E "$(lsblk -no PKNAME "$TARGET_MOUNT" 2>/dev/null)" | head -n1)
[ -z "$SSD_NAME" ] && SSD_NAME=$(lsblk -lno PKNAME,MOUNTPOINTS | grep "$TARGET_MOUNT" | awk '{print $1}')

# 2. Run bypass provisioning mode if the /sys path exists
if [ -n "$SSD_NAME" ] && [ -d "/sys/block/$SSD_NAME/device/scsi_disk" ]; then
    echo "unmap" | tee /sys/block/$SSD_NAME/device/scsi_disk/*/provisioning_mode > /dev/null
fi

# 3. Execute TRIM on the target mount point
fstrim -v "$TARGET_MOUNT"

echo "Done! TRIM successfully bypassed for /dev/${SSD_NAME:-unknown} at $TARGET_MOUNT."
EOF

# Permanently inject the selected mount point name into the target script
sed -i "s|REPLACE_WITH_MOUNT|$TARGET_MOUNT|g" "$TARGET_SCRIPT"

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
