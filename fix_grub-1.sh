#!/bin/bash
# ==============================================================
# Ubuntu GRUB 一键修复脚本（支持 BIOS + MBR）
# 自动检测根分区、引导类型、修复 grub.cfg 缺失
# 适合 LiveCD ("Try Ubuntu") 环境使用
# ==============================================================

set -e
echo "=== 🧩 Ubuntu GRUB 自动修复启动 ==="

# -------------------------------
# 检测根分区（ext4）
# -------------------------------
ROOT_PART=$(blkid -t TYPE=ext4 -o device | head -n1)
if [ -z "$ROOT_PART" ]; then
    echo "❌ 未检测到 ext4 根分区，请手动运行：lsblk -f"
    exit 1
fi

if [ ! -b "$ROOT_PART" ]; then
    echo "❌ 根分区设备无效: $ROOT_PART"
    exit 1
fi

echo "🧱 检测到根分区：$ROOT_PART"

# -------------------------------
# 推导主磁盘设备
# -------------------------------
DISK_DEV=$(echo "$ROOT_PART" | sed -E 's/p?[0-9]+$//')
if [ ! -b "$DISK_DEV" ]; then
    echo "❌ 无法识别主磁盘设备，请检查：$DISK_DEV"
    exit 1
fi
echo "💽 对应磁盘：$DISK_DEV"

# -------------------------------
# 检查分区表类型（MBR/GPT）
# -------------------------------
TABLE_TYPE=$(parted -s "$DISK_DEV" print | grep "Partition Table" | awk '{print $3}')
echo "📋 分区表类型：$TABLE_TYPE"
if [ "$TABLE_TYPE" = "gpt" ]; then
    echo "⚠️ 检测到 GPT 分区表（BIOS 模式需有 BIOS Boot 分区）"
    echo "   若无该分区，grub-install 可能失败。"
fi

# -------------------------------
# 挂载分区
# -------------------------------
echo "📦 挂载根分区..."
mkdir -p /mnt
mount "$ROOT_PART" /mnt

# 检测并挂载 /boot
BOOT_PART=$(lsblk -fpno NAME,FSTYPE,MOUNTPOINT | grep -E "vfat|ext4" | grep boot | awk '{print $1}' | head -n1)
if [ -n "$BOOT_PART" ]; then
    echo "📦 检测到独立 /boot 分区：$BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ /boot 挂载失败（忽略）"
fi

# -------------------------------
# 挂载系统目录
# -------------------------------
echo "🔗 挂载系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "/mnt$i"
done

# -------------------------------
# 进入 chroot 修复 GRUB
# -------------------------------
echo "🔧 正在修复 GRUB..."

chroot /mnt /bin/bash <<EOF
set -e
echo "🧹 清理 grubenv..."
rm -f /boot/grub/grubenv || true
grub-editenv /boot/grub/grubenv create || true

echo "⚙️ 安装 GRUB 到 $DISK_DEV..."
grub-install --target=i386-pc --recheck "$DISK_DEV" || {
    echo "⚠️ grub-install 失败，尝试 --force"
    grub-install --target=i386-pc --recheck --force "$DISK_DEV"
}

# 若 grub.cfg 不存在则自动创建
if [ ! -f /boot/grub/grub.cfg ]; then
    echo "⚙️ grub.cfg 缺失，尝试重新生成..."
    update-grub || grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "🧩 已检测到 grub.cfg，执行 update-grub..."
    update-grub
fi

echo "✅ GRUB 修复完成"
EOF

# -------------------------------
# 卸载挂载
# -------------------------------
echo "🔽 卸载挂载点..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf "/mnt$i" 2>/dev/null || true
done
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成！现在可以执行以下命令重启："
echo "    sudo reboot"
