#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Jalankan skrip ini sebagai root (sudo ./install.sh)"
  exit 1
fi

echo "=========================================="
echo "      DAFTAR DISK YANG TERSEDIA           "
echo "=========================================="
lsblk -d -o NAME,SIZE,MODEL,ROTA,TRAN | grep -v "loop"
echo "=========================================="

# Minta input target drive dari user
read -p "Masukkan nama drive target (contoh: sdb, sdc): " TARGET_DRIVE

# Validasi input
if [ ! -b "/dev/$TARGET_DRIVE" ]; then
    echo "[-] Error: Drive /dev/$TARGET_DRIVE tidak ditemukan!"
    exit 1
fi

TARGET_SCRIPT="/usr/local/bin/trim-bypass.sh"
OVERRIDE_DIR="/etc/systemd/system/fstrim.service.d"

echo "[1/4] Membuat $TARGET_SCRIPT untuk drive /dev/$TARGET_DRIVE..."
cat << EOF > "$TARGET_SCRIPT"
#!/bin/bash
# Paksa ubah provisioning_mode ke unmap untuk drive $TARGET_DRIVE
echo "unmap" | tee /sys/block/$TARGET_DRIVE/device/scsi_disk/*/provisioning_mode > /dev/null

# Jalankan TRIM
fstrim -v /media/ssd

echo "Done! TRIM berhasil di-bypass untuk /dev/$TARGET_DRIVE."
EOF

# Beri akses eksekusi ke skrip bypass
chmod +x "$TARGET_SCRIPT"

echo "[2/4] Mengatur override systemd fstrim.service..."
mkdir -p "$OVERRIDE_DIR"
cat << 'EOF' > "$OVERRIDE_DIR/override.conf"
[Service]
ExecStart=
ExecStart=/usr/local/bin/trim-bypass.sh
PrivateDevices=no
PrivateNetwork=yes
PrivateUsers=no
# WAJIB 'no' agar skrip bisa menulis ke direktori /sys/block/
ProtectKernelTunables=no
ProtectKernelModules=no
ProtectControlGroups=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@default @file-system @basic-io @system-service
EOF

echo "[3/4] Memperbarui daemon dan mengaktifkan fstrim.timer..."
systemctl daemon-reload
systemctl enable --now fstrim.timer

echo "[4/4] Pengaturan selesai! Menguji eksekusi fstrim.service..."
systemctl start fstrim.service

echo "=== Status Eksekusi Terakhir ==="
systemctl status fstrim.service --no-pager