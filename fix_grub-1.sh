#!/bin/bash
# ==============================================================
# 🧩 Ubuntu GRUB 一键修复脚本（支持 BIOS + GPT/MBR 自动检测）
# 适用于 LiveCD ("Try Ubuntu") 环境。
# 会自动检测根分区、检查分区表类型、修复 grub.cfg 缺失。
# ==============================================================
set -e

echo "=== 🧱 启动 Ubuntu GRUB 自动修复工具 ==="
echo

# ---------- 自动检测根分区 ----------
ROOT_PART=$(lsblk -fpno NAME,FSTYPE,MOUNTPOINT | awk '$2=="ext4" && $3==""{print $1; exit}')
if [ -z "$ROOT_PART" ]; then
    echo "❌ 未检测到 ext4 类型的根分区，请使用 lsblk -f 手动确认！"
    exit 1
fi

echo "✅ 检测到根分区: $ROOT_PART"

# ---------- 推导磁盘设备 ----------
DISK_DEV=$(echo "$ROOT_PART" | sed -E 's/[0-9]+$//')
if [ ! -b "$DISK_DEV" ]; then
    echo "❌ 无法识别磁盘设备: $DISK_DEV"
    exit 1
fi
echo "💽 对应磁盘: $DISK_DEV"

# ---------- 检查分区表类型 ----------
TABLE_TYPE=$(parted -s "$DISK_DEV" print | grep "Partition Table" | awk '{print $3}')
echo "📋 分区表类型: $TABLE_TYPE"

if [ "$TABLE_TYPE" = "gpt" ]; then
    echo "⚠️ 检测到 GPT 分区表 (BIOS 启动模式)"
    echo "🔍 检查是否存在 BIOS Boot 分区 (1MB, 无格式化)..."
    BIOS_BOOT_EXIST=$(parted -s "$DISK_DEV" print | grep -i 'bios_grub' || true)
    if [ -z "$BIOS_BOOT_EXIST" ]; then
        echo "🚨 未检测到 BIOS Boot 分区！GRUB 可能无法写入。"
        echo "👉 建议创建 1MB BIOS Boot 分区:"
        echo "    sudo parted $DISK_DEV mkpart biosboot 1MiB 2MiB"
        echo "    sudo parted $DISK_DEV set 1 bios_grub on"
        echo "继续修复可能失败，按 Ctrl+C 取消，或按 Enter 继续。"
        read
    fi
fi

# ---------- 挂载根分区 ----------
echo "📦 挂载根分区..."
mkdir -p /mnt
mount "$ROOT_PART" /mnt

# ---------- 检查是否有 /boot 分区 ----------
BOOT_PART=$(lsblk -fpno NAME,FSTYPE | awk '$2=="vfat" || $2=="ext4"{print $1}' | grep -v "$ROOT_PART" | head -n1)
if [ -n "$BOOT_PART" ]; then
    echo "📦 检测到 /boot 分区: $BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ 挂载 /boot 失败（忽略）"
fi

# ---------- 绑定系统目录 ----------
echo "🔗 绑定系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "/mnt$i"
done

# ---------- 修复 grub ----------
echo "🔧 进入 chroot 环境执行修复..."
chroot /mnt /bin/bash <<EOF
set -e
echo "🧹 清理旧 grubenv..."
rm -f /boot/grub/grubenv
grub-editenv /boot/grub/grubenv create || true

echo "🔍 检查 grub.cfg..."
if [ ! -f /boot/grub/grub.cfg ]; then
    echo "⚙️ 检测到 grub.cfg 丢失，正在重新生成..."
    update-grub
else
    echo "✅ grub.cfg 已存在，尝试更新..."
    update-grub
fi

echo "⚙️ 重新安装 GRUB 到 $DISK_DEV..."
grub-install --target=i386-pc --recheck "$DISK_DEV" || echo "⚠️ grub-install 可能报告警告，可忽略。"

echo "🧩 再次更新 grub.cfg..."
update-grub

echo "✅ chroot 内修复完成。"
EOF

# ---------- 卸载 ----------
echo "🔽 卸载挂载点..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf "/mnt$i" 2>/dev/null || true
done
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成！请现在重启系统："
echo "    sudo reboot"
echo
echo "💡 若仍进入 grub> 提示符，可手动输入："
echo "    set root=(hd0,msdos5)"
echo "    linux /boot/vmlinuz root=$ROOT_PART ro"
echo "    initrd /boot/initrd.img"
echo "    boot"
