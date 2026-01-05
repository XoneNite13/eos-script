#!/bin/bash
set -e

echo "=============================="
echo "  SWAP /dev/vdc1 + XMRIG STATIC"
echo "=============================="

SWAP_DEV="/dev/vdc1"

echo "== Cek device swap target: $SWAP_DEV =="

if ! lsblk | grep -q "$(basename "$SWAP_DEV")"; then
  echo "!!! ERROR: $SWAP_DEV tidak ditemukan di lsblk"
  exit 1
fi

# Pastikan tidak di-mount sebagai filesystem biasa
if mount | grep -q "$SWAP_DEV"; then
  echo "!!! ERROR: $SWAP_DEV sedang di-mount sebagai filesystem, tidak bisa dipakai swap."
  echo "Silakan unmount dulu secara manual."
  exit 1
fi

echo "== Mematikan swap lama (jika ada) =="
swapoff -a || true

echo "== Membuat $SWAP_DEV sebagai swap =="

mkswap "$SWAP_DEV"
swapon "$SWAP_DEV"

echo "== Swap aktif sekarang: =="
swapon --show

# Tambah ke fstab bila belum ada
if ! grep -q "$SWAP_DEV" /etc/fstab 2>/dev/null; then
  echo "$SWAP_DEV none swap sw 0 0" >> /etc/fstab
fi

echo "== Tuning swap (swappiness / cache pressure) =="

# Pastikan /etc/sysctl.conf ada
if [ ! -f /etc/sysctl.conf ]; then
  touch /etc/sysctl.conf
fi

if grep -q "^vm.swappiness" /etc/sysctl.conf; then
  sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
else
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

if grep -q "^vm.vfs_cache_pressure" /etc/sysctl.conf; then
  sed -i 's/^vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=50/' /etc/sysctl.conf
else
  echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
fi

sysctl -p || true

echo "== SWAP via $SWAP_DEV SELESAI =="

########################################
# INSTALL TOOLS + DOWNLOAD XMRIG STATIC
########################################

echo "== Install tool pendukung (screen, curl, wget, tar) =="

apt update -y
apt install -y screen curl wget tar

cd /root

XMRIG_VER="6.24.0"
XMRIG_DIR="xmrig-${XMRIG_VER}"
XMRIG_TAR="xmrig-${XMRIG_VER}-linux-static-x64.tar.gz"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/${XMRIG_TAR}"

# Matikan miner lama kalau ada dan hapus file lama
if screen -list | grep -q "\.miner"; then
  screen -S miner -X quit || true
fi
rm -rf "${XMRIG_DIR}" "${XMRIG_TAR}"

echo "== Download XMRig static =="
wget -O "${XMRIG_TAR}" "${XMRIG_URL}"

echo "== Extract XMRig =="
tar -xzf "${XMRIG_TAR}"

cd "${XMRIG_DIR}"

#############################################
# CONFIG XMRIG UNTUK UNMINEABLE RX
#############################################

echo "== Membuat config.json (rx.unmineable.com) =="

# Worker name: angka random saja (maks 10 digit)
RAND_RAW="${RANDOM}${RANDOM}${RANDOM}"
WORKER_NAME="${RAND_RAW:0:10}"      # contoh: 8374629102
POOL_USER="1853902404.${WORKER_NAME}"

cat <<EOF > config.json
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "priority": 5,
    "huge-pages": true
  },
  "randomx": {
    "1gb-pages": false,
    "init": -1,
    "mode": "auto",
    "numa": true
  },
  "pools": [
    {
      "url": "rx.unmineable.com:3333",
      "user": "${POOL_USER}",
      "pass": "x",
      "algo": "rx/0",
      "keepalive": true,
      "tls": false
    }
  ]
}
EOF

echo "== config.json dibuat =="
echo "Pool   : rx.unmineable.com:3333"
echo "User   : ${POOL_USER}"
echo "Worker : ${WORKER_NAME}"

#############################
# JALANKAN MINER DI SCREEN
#############################

echo "== Menyalakan xmrig di screen 'miner' =="

# Matikan screen lama kalau ada
if screen -list | grep -q "\.miner"; then
  screen -S miner -X quit || true
fi

screen -dmS miner ./xmrig -c config.json

echo ""
echo "======================================="
echo "  SETUP SELESAI! MINER SUDAH BERJALAN  "
echo "======================================="
echo "Swap device : $SWAP_DEV"
echo "Screen name : miner"
echo "Worker      : ${WORKER_NAME}"
echo ""
echo "Cek screen : screen -r miner"
echo "Detach     : CTRL + A lalu D"
echo "Cek swap   : swapon --show"
echo "======================================="
