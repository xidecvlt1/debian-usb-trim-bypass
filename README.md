# Debian USB-to-SATA TRIM Bypass (Weekly Systemd Service)

Skrip otomatis untuk mengaktifkan dan mem-bypass fitur **TRIM** pada SSD yang terhubung melalui adapter/casing **USB-to-SATA** (UAS/BOT) di Linux (Debian 13 / Ubuntu). 

Secara bawaan, Linux memblokir perintah TRIM pada koneksi USB yang dianggap tidak mendukung *Unmap*. Skrip ini memaksa pengaturan `provisioning_mode` ke `unmap` lalu mengintegrasikannya ke **`fstrim.timer`** bawaan systemd agar berjalan secara otomatis setiap minggu.

## Fitur
- **Interactive Drive Selection**: Displays available disks and lets you select the target drive.
- **Systemd Drop-in Override**: Utilizes the override structure to keep configurations safe from being overwritten during system updates.
- **Sandbox Fix**: Relaxes systemd sandbox restrictions `ProtectKernelTunables=no` to grant the script permission to write to `/sys/block/`.
- **Permanent Weekly Schedule**: Automatically stays active every week via `fstrim.timer`.

---

## Quick Install

Jalankan perintah ini langsung di terminal Anda:

```bash
curl -O https://raw.githubusercontent.com/xidecvlt1/debian-usb-trim-bypass/main/bypass-trim-install.sh
chmod +x bypass-trim-install.sh
./bypass-trim-install.sh
```