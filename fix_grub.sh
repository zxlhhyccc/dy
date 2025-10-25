#!/bin/bash
# 修复 BIOS+MBR Ubuntu GRUB 引导
# 在 LiveCD 下运行
set -e

# 配置分区（根据实际情况修改）
ROOT_PART=/dev/sda5
BOOT_PART=""  # 如果 /boot 是单独分区，写如 /dev/sda1，否则留空
DISK=/dev/sda

echo "挂载根分区: $ROOT_PART"
sudo mount $ROOT_PART /mnt

if [ -n "$BOOT_PART" ]; then
    echo "挂载 /boot 分区: $BOOT_PART"
    sudo mount $BOOT_PART /mnt/boot
fi

echo "挂载虚拟文件系统"
for i in /dev /dev/pts /proc /sys /run; do
    sudo mount --bind $i /mnt$i
done

echo "进入 chroot 环境安装 GRUB"
sudo chroot /mnt /bin/bash -c "
set -e
echo '重新安装 GRUB 到 MBR: $DISK'
grub-install --target=i386-pc --recheck $DISK
update-grub
"

echo "退出 chroot 并卸载虚拟文件系统"
for i in /run /sys /proc /dev/pts /dev; do
    sudo umount /mnt$i
done

if [ -n "$BOOT_PART" ]; then
    sudo umount /mnt/boot
fi
sudo umount /mnt

echo "MBR + GRUB 修复完成，请重启系统"
