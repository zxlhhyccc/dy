#!/bin/bash
# ==============================================================
# Ubuntu GRUB 一键修复脚本（适用于 BIOS 模式虚拟机）
# 适合在 LiveCD 下执行，例如 "Try Ubuntu" 模式
# ==============================================================

set -e

echo "=== Ubuntu GRUB 修复脚本启动 ==="
echo

# 检测根分区（ext4 类型）
ROOT_PART=$(lsblk -fpno NAME,FSTYPE | grep ext4 | head -n1 | awk '{print $1}')
if [ -z "$ROOT_PART" ]; then
    echo "❌ 未找到 ext4 根分区，请手动指定！"
    exit 1
fi

echo "🧱 检测到根分区：$ROOT_PART"

# 检查是否存在独立的 /boot 分区
BOOT_PART=$(lsblk -fpno NAME,MOUNTPOINT,FSTYPE | grep vfat | awk '{print $1}' | head -n1)

# 挂载根分区
echo "📦 挂载根分区..."
mount "$ROOT_PART" /mnt

# 如果存在 /boot 分区，则挂载它
if [ -n "$BOOT_PART" ]; then
    echo "📦 检测到 /boot 分区：$BOOT_PART"
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot || echo "⚠️ 挂载 /boot 失败（忽略）"
fi

# 绑定系统目录
echo "🔗 绑定系统目录..."
for i in /dev /dev/pts /proc /sys /run; do
    mount --bind $i /mnt$i
done

# 进入 chroot 环境修复 GRUB
echo "🔧 进入 chroot 环境修复..."
chroot /mnt /bin/bash <<'EOF'
set -e
echo "🧹 清理并重新创建 grubenv..."
rm -f /boot/grub/grubenv
grub-editenv /boot/grub/grubenv create

echo "⚙️ 重新安装 GRUB 到 MBR (/dev/sda)..."
grub-install --target=i386-pc /dev/sda --recheck

echo "🧩 生成 grub.cfg..."
update-grub

echo "✅ GRUB 修复完成，准备退出 chroot..."
EOF

# 卸载所有挂载点
echo "🔽 卸载挂载点..."
for i in /run /sys /proc /dev/pts /dev; do
    umount -lf /mnt$i 2>/dev/null || true
done
umount -lf /mnt/boot 2>/dev/null || true
umount -lf /mnt 2>/dev/null || true

echo
echo "🎉 修复完成！现在可以安全重启系统："
echo "    sudo reboot"
echo

