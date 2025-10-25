#!/bin/bash
# ==============================================================
# 🔧 Ubuntu GRUB 一键修复脚本（自动识别 BIOS / UEFI）
# 适用于 LiveCD (“Try Ubuntu”) 环境
# 支持 MBR、GPT、UEFI 启动修复
# ==============================================================
set -e

echo "=== 🧩 启动 Ubuntu GRUB 自动修复 ==="

# -------------------------------
# 1️⃣ 检测根分区（ext4）
# -------------------------------
ROOT_PART=$(blkid -t TYPE=ext4 -o device | head -n1)
if [ -z "$ROOT_PART" ]; then
    echo "❌ 未检测到 ext4 根分区，请运行：lsblk -f"
    exit 1
fi

if [ ! -b "$ROOT_PART" ]; then
    echo "❌ 根分区设备无效: $ROOT_PART"
    exit 1
fi

echo "🧱 检测到根分区：$ROOT_PART"

# -------------------------------
# 2️⃣ 推导主磁盘设备 (/dev/sda)
# -------------------------------
DISK_DEV=$(echo "$ROOT_PART" | sed -E 's/p?[0-9]+$//')
if [ ! -b "$DISK_DEV" ]; then
    echo "❌ 无法识别主磁盘设备：$DISK_DEV"
    exit 1
fi
echo "💽 主磁盘设备：$DISK_DEV"

# -------------------------------
# 3️⃣ 检查分区表类型（MBR/GPT）
# -------------------------------
TABLE_TYPE=$(parted -s "$DISK_DEV" print | grep "Partition Table" | awk '{print $3}')
echo "📋 分区表类型：$TABLE_TYPE"

# -------------------------------
# 4️⃣ 检测当前启动模式（UEFI / BIOS）
# -------------------------------
if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
    echo "🧠 检测到 UEFI 启动模式"
else
    BOOT_MODE="BIOS"
    echo "🧠 检测到 BIOS 启动模式"
fi

# -------------------------------
# 5️⃣ 挂载根分区
# -------------------------------
echo "📦 挂载根分区..."
mkdir -p /mnt
mount "$ROOT_PART" /mnt

# -------------------------------
# 6️⃣ 检测并挂载 boot / efi 分区
# -------------------------------
BOOT_PART=""
EFI_PART=""

# 检测 /boot 分区（ext4）
BOOT_PART=$(lsblk -fpno NAME,FSTYPE,MOUNTPOINT | grep -E "ext4" | grep boot | awk '{print $1}' | head -n1)
# 检测 EFI 分区（vfat）
EFI_PART=$(lsblk -fpno NAME,FSTYPE,MOUNTPOINT | grep -E "vfat" | grep efi | awk '{print $1}' | head -n1)

if [ -n "$BOOT_PART" ]; then
    echo "📦 检测到独立 /boot 分区：$BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ /boot 挂载失败（忽略）"
fi

if [ "$BOOT_MODE" = "UEFI" ]; then
    if [ -z "$EFI_PART" ]; then
        EFI_PART=$(blkid -t TYPE=vfat -o device | head -n1)
    fi
    if [ -n "$EFI_PART" ]; then
        echo "📦 挂载 EFI 分区：$EFI_PART"
        mkdir -p /mnt/boot/efi
        mount "$EFI_PART" /mnt/boot/efi || echo "⚠️ EFI 挂载失败（忽略）"
    else
        echo "⚠️ 未找到 EFI 分区（可能系统结构异常）"
    fi
fi

# -------------------------------
# 7️⃣ 绑定系统目录
# -------------------------------
echo "🔗 挂载系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind "$i" "/mnt$i"
done

# -------------------------------
# 8️⃣ 修复 GRUB
# -------------------------------
echo "🔧 开始修复 GRUB..."

chroot /mnt /bin/bash <<EOF
set -e

echo "🧹 清理 grubenv..."
rm -f /boot/grub/grubenv || true
grub-editenv /boot/grub/grubenv create || true

if [ "$BOOT_MODE" = "UEFI" ]; then
    echo "⚙️ 执行 grub-install (UEFI)..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck || {
        echo "⚠️ grub-install (UEFI) 失败，尝试 --force"
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --force
    }
else
    echo "⚙️ 执行 grub-install (BIOS)..."
    grub-install --target=i386-pc --recheck "$DISK_DEV" || {
        echo "⚠️ grub-install (BIOS) 失败，尝试 --force"
        grub-install --target=i386-pc --recheck --force "$DISK_DEV"
    }
fi

echo "🧩 更新 grub.cfg..."
if [ ! -f /boot/grub/grub.cfg ]; then
    echo "⚙️ grub.cfg 缺失，重新生成..."
    update-grub || grub-mkconfig -o /boot/grub/grub.cfg
else
    update-grub
fi

echo "✅ GRUB 修复完成"
EOF

# -------------------------------
# 9️⃣ 卸载挂载
# -------------------------------
echo "🔽 卸载挂载点..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf "/mnt$i" 2>/dev/null || true
done
umount -lf /mnt/boot/efi 2>/dev/null || true
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成！可以重启："
echo "    sudo reboot"

