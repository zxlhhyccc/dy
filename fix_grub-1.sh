#!/bin/bash
# ==============================================================
# Ubuntu BIOS+MBR GRUB 一键修复脚本
# 适用于 LiveCD ("Try Ubuntu") 环境
# ==============================================================
set -e

echo "=== 🧩 启动 GRUB 修复脚本 ==="

# ---- 自动检测根分区 ----
ROOT_PART=$(blkid -t TYPE=ext4 -o device | head -n1)

if [ -z "$ROOT_PART" ]; then
    echo "❌ 未检测到 ext4 根分区，请手动查看：lsblk -f"
    exit 1
fi

if [ ! -b "$ROOT_PART" ]; then
    echo "❌ 检测到的根分区设备不存在: $ROOT_PART"
    exit 1
fi

echo "🧱 检测到根分区：$ROOT_PART"

# ---- 推导主磁盘设备 (/dev/sda) ----
DISK_DEV=$(echo "$ROOT_PART" | sed -E 's/p?[0-9]+$//')
if [ ! -b "$DISK_DEV" ]; then
    echo "❌ 无法识别主磁盘设备，请检查：$DISK_DEV"
    exit 1
fi

echo "💽 对应磁盘：$DISK_DEV"

# ---- 挂载根分区 ----
echo "📦 挂载根分区..."
mkdir -p /mnt
mount "$ROOT_PART" /mnt

# ---- 挂载 /boot （如果存在）----
BOOT_PART=$(blkid -t TYPE=vfat -o device | head -n1)
if [ -n "$BOOT_PART" ] && [ -b "$BOOT_PART" ]; then
    echo "📦 检测到 /boot 分区：$BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ /boot 挂载失败，忽略"
fi

# ---- 挂载系统目录 ----
echo "🔗 挂载系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "/mnt$i"
done

# ---- 修复 GRUB ----
echo "🔧 修复 GRUB..."
chroot /mnt /bin/bash <<EOF
set -e
echo "🧹 清理 grubenv..."
rm -f /boot/grub/grubenv || true
grub-editenv /boot/grub/grubenv create || true

echo "⚙️ 安装 GRUB 到 $DISK_DEV..."
grub-install --target=i386-pc --recheck "$DISK_DEV"

echo "🧩 更新 grub.cfg..."
update-grub

echo "✅ GRUB 修复完成"
EOF

# ---- 卸载挂载 ----
echo "🔽 卸载挂载..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf "/mnt$i" 2>/dev/null || true
done
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成，请执行以下命令重启："
echo "    sudo reboot"
