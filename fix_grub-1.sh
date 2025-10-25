#!/bin/bash
# ==============================================================
# Ubuntu GRUB 一键修复脚本（适用于 BIOS 模式虚拟机）
# 在 LiveCD (Try Ubuntu) 环境下执行
# ==============================================================

set -e

echo "=== 🧩 Ubuntu GRUB 修复脚本启动 ==="
echo

# 检测根分区（ext4）
ROOT_PART=$(lsblk -fpno NAME,FSTYPE | awk '$2=="ext4"{print $1; exit}')
if [ -z "$ROOT_PART" ]; then
    echo "❌ 未找到 ext4 类型的根分区，请手动确认 (lsblk -f)"
    exit 1
fi

# 检查设备文件是否存在
if [ ! -b "$ROOT_PART" ]; then
    echo "❌ 检测到的分区不存在: $ROOT_PART"
    exit 1
fi

echo "🧱 检测到根分区: $ROOT_PART"

# 自动推导磁盘设备 (/dev/sda)
DISK_DEV=$(echo "$ROOT_PART" | sed -E 's/[0-9]+$//')
if [ ! -b "$DISK_DEV" ]; then
    echo "❌ 无法识别磁盘设备，请检查: $DISK_DEV"
    exit 1
fi
echo "💽 对应磁盘: $DISK_DEV"

# 挂载根分区
echo "📦 挂载根分区..."
mkdir -p /mnt
mount "$ROOT_PART" /mnt

# 检测 /boot 分区
BOOT_PART=$(lsblk -fpno NAME,FSTYPE | awk '$2=="vfat"{print $1; exit}')
if [ -n "$BOOT_PART" ]; then
    echo "📦 检测到 /boot (VFAT) 分区: $BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ 挂载 /boot 失败（忽略）"
fi

# 绑定系统目录
echo "🔗 绑定系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "/mnt$i"
done

# 进入 chroot 环境
echo "🔧 修复 GRUB..."
chroot /mnt /bin/bash <<EOF
set -e
echo "🧹 清理并重建 grubenv..."
rm -f /boot/grub/grubenv
grub-editenv /boot/grub/grubenv create || true

echo "⚙️ 安装 GRUB 到 $DISK_DEV..."
grub-install --target=i386-pc "$DISK_DEV" --recheck

echo "🧩 更新 grub.cfg..."
update-grub

echo "✅ GRUB 修复完成，准备退出 chroot..."
EOF

# 卸载挂载点
echo "🔽 清理挂载..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf "/mnt$i" 2>/dev/null || true
done
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成！现在可以安全重启系统："
echo "    sudo reboot"
echo
