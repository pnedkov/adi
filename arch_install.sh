#!/bin/bash
set -e

# Drive to install to
DRIVE='sda'

# File system for root and home: xfs/ext4
FS='xfs'

# LVM group name
LVM_GROUP='archvg'

# Hostname
HOSTNAME='archy'

# Encryption device - encrypts everything except /boot (leave blank to disable)
ENC_DEV_NAME='cryptlvm'

# Passphrase used to encrypt the drive (leave blank to be prompted)
ENC_DEV_PASSPHRASE='apasswd'

# Root password (leave blank to be prompted)
ROOT_PASSWORD='bpasswd'

# Main user to create (by default, added to wheel group)
USER_NAME='plamen'

# The main user's password (leave blank to be prompted)
USER_PASSWORD='cpasswd'

# System timezone
TIMEZONE='America/Los_Angeles'

# System keymap: us/dvorak
KEYMAP='us'

# CPU manufacturer: intel/amd or blank
CPU_MICROCODE='intel'

# Video driver: i915/nvidia/nouveau/radeon/vesa or blank
VIDEO_DRIVER=''

# Packages (comment to disable)
PACKAGES_BASE='net-tools ntp openssh sudo wget vim bash-completion'
PACKAGES_FONTS='terminus-font ttf-hack ttf-anonymous-pro ttf-dejavu ttf-freefont ttf-liberation'
#PACKAGES_X='xorg-server xorg-apps xorg-xinit xterm'
#PACKAGES_WM='plasma-desktop plasma-nm sddm sddm-kcm powerdevil alsa-utils pulseaudio plasma-pa'
PACKAGES_USER_CLI='htop netcat'
#PACKAGES_USER_GUI='terminator chromium'


#
# Setup
#
setup() {
    local boot_dev="/dev/$DRIVE"1
    local arch_dev="/dev/$DRIVE"2
    local lvm_pv="$arch_dev"

    headline "Creating partitions"
    partition_drive "/dev/$DRIVE"

    if [ -n "$ENC_DEV_NAME" ]
    then
        local lvm_pv="/dev/mapper/$ENC_DEV_NAME"

        headline "Encrypting partition"
        if [ -z "$ENC_DEV_PASSPHRASE" ]
        then
            echo "Enter a passphrase to encrypt $arch_dev: "
            stty -echo
            read ENC_DEV_PASSPHRASE
            stty echo
        fi

        encrypt_drive "$arch_dev"
    fi

    headline "Setting up LVM"
    setup_lvm "$lvm_pv"

    headline "Formatting filesystems"
    format_filesystems "$boot_dev" "$LVM_GROUP"

    headline "Mounting filesystems"
    mount_filesystems "$boot_dev"

    headline "Installing base system"
    install_base

    headline "Chrooting..."
    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot

    if [ -f /mnt/setup.sh ]
    then
        echo -e "\n\n\e[1;31m ERROR: Script failed, not unmounting filesystems so you can investigate.\e[0m"
        echo "Make sure you run \'$0 clean\' before you run this script again."
    else
        headline "Unmounting filesystems"
        unmount_filesystems

        echo -e "\n\n\e[1;32m Done! Reboot system.\e[0m\n"
    fi
}


#
# Configure
#
configure() {
    local boot_dev="/dev/$DRIVE"1
    local arch_dev="/dev/$DRIVE"2

    headline "Installing additional packages"
    install_packages

    headline "Clearing package tarballs"
    clean_packages

    headline "Setting hostname"
    set_hostname "$HOSTNAME"

    headline "Setting hosts file"
    set_hosts "$HOSTNAME"

    headline "Setting timezone"
    set_timezone "$TIMEZONE"

    headline "Setting locale"
    set_locale

    headline "Configuring keyboard in console"
    set_vconsole

    headline "Configuring initial ramdisk"
    set_initcpio

    headline "Configuring UEFI boot"
    set_bootctl "$arch_dev"

    headline "Configuring netowrk"
    set_wired_network

    headline "Setting initial daemons"
    set_daemons

    headline "Configuring sudo"
    set_sudoers

    headline "Setting root password"
    if [ -z "$ROOT_PASSWORD" ]
    then
        echo 'Enter the root password:'
        stty -echo
        read ROOT_PASSWORD
        stty echo
    fi
    set_root_password "$ROOT_PASSWORD"

    headline "Creating user $USER_NAME"
    if [ -z "$USER_PASSWORD" ]
    then
        echo "Enter the password for user $USER_NAME"
        stty -echo
        read USER_PASSWORD
        stty echo
    fi
    create_user "$USER_NAME" "$USER_PASSWORD"

    rm -f /setup.sh
}


partition_drive() {
    local dev="$1"; shift

    parted -s "$dev" \
        mklabel gpt \
        mkpart primary 0% 512M \
        set 1 esp on \
        mkpart primary 512M 100% \
        set 2 lvm on
}

###

encrypt_drive() {
    local dev="$1"; shift

    echo -en "$ENC_DEV_PASSPHRASE" | cryptsetup luksFormat "$dev"
    echo -en "$ENC_DEV_PASSPHRASE" | cryptsetup luksOpen "$dev" "$ENC_DEV_NAME"
}

setup_lvm() {
    local lvm_pv_dev="$1"; shift

    pvcreate "$lvm_pv_dev"
    vgcreate "$LVM_GROUP" "$lvm_pv_dev"

    lvcreate -L 2G "$LVM_GROUP" -n swap

    lvcreate -L 16G "$LVM_GROUP" -n root

    lvcreate -l 100%FREE "$LVM_GROUP" -n home

    #vgchange -ay
}

format_filesystems() {
    local boot_dev="$1"; shift

    mkfs.vfat -F32 $boot_dev

    mkfs.$FS /dev/$LVM_GROUP/root
    mkfs.$FS /dev/$LVM_GROUP/home

    mkswap /dev/$LVM_GROUP/swap
}

mount_filesystems() {
    local boot_dev="$1"; shift

    mount /dev/$LVM_GROUP/root /mnt
    mkdir /mnt/boot
    mkdir /mnt/home
    mount "$boot_dev" /mnt/boot
    mount /dev/$LVM_GROUP/home /mnt/home
    swapon /dev/$LVM_GROUP/swap
}

install_base() {

    echo 'Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

    pacstrap /mnt base base-devel
    genfstab /mnt >> /mnt/etc/fstab
    cp -f /etc/resolv.conf /mnt/etc/resolv.conf
}

unmount_filesystems() {

    umount -R /mnt
    swapoff /dev/$LVM_GROUP/swap
    vgchange -an
    if [ -n "$ENC_DEV_NAME" ]
    then
        cryptsetup luksClose /dev/mapper/$ENC_DEV_NAME
    fi
}

###

install_packages() {
    local packages=''

    # CPU microcode
    if [ -n "$CPU_MICROCODE" ]
    then
        packages+=" $CPU_MICROCODE-ucode"
    fi

    # Base
    if [ -n "$PACKAGES_BASE" ]
    then
        packages+=" $PACKAGES_BASE"
    fi

    # Fonts
    if [ -n "$PACKAGES_FONTS" ]
    then
        packages+=" $PACKAGES_FONTS"
    fi

    # X
    if [ -n "$PACKAGES_X" ]
    then
        packages+=" $PACKAGES_X"
    fi

    # WM
    if [ -n "$PACKAGES_WM" ]
    then
        packages+=" $PACKAGES_WM"
    fi

    # User apps CLI
    if [ -n "$PACKAGES_USER_CLI" ]
    then
        packages+=" $PACKAGES_USER_CLI"
    fi

    # User apps GUI
    if [ -n "$PACKAGES_USER_GUI" ]
    then
        packages+=" $PACKAGES_USER_GUI"
    fi

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        packages+=' xf86-video-intel libva-intel-driver'
    elif [ "$VIDEO_DRIVER" = "nvidia" ]
    then
        packages+=' nvidia'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        packages+=' xf86-video-nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        packages+=' xf86-video-ati'
    elif [ "$VIDEO_DRIVER" = "vesa" ]
    then
        packages+=' xf86-video-vesa'
    fi

    pacman -Sy --noconfirm $packages
}

clean_packages() {
    yes | pacman -Scc
}

set_hostname() {
    local hostname="$1"; shift

    echo "$hostname" > /etc/hostname
}

set_hosts() {
    local hostname="$1"; shift

    cat > /etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost $hostname
::1       localhost.localdomain localhost $hostname
EOF
}

set_timezone() {
    local timezone="$1"; shift

    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

set_locale() {
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    locale > /etc/locale.conf
}

set_vconsole() {
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "FONT=ter-g16n" >> /etc/vconsole.conf
}

set_initcpio() {
    local vid

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        vid='i915'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        vid='nouveau'
    elif [ "$VIDEO_DRIVER" = "nvidia" ]
    then
        vid='nvidia'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        vid='radeon'
    fi

    if [ -n "$ENC_DEV_NAME" ]
    then
        MY_HOOKS="base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck"
    else
        MY_HOOKS="base udev autodetect keyboard keymap consolefont modconf block lvm2 filesystems fsck"
    fi

    # Set MODULES in /etc/mkinitcpio.conf
    sed -i -e "s/^MODULES=.*/MODULES=\"$FS $vid\"/" /etc/mkinitcpio.conf

    # Set HOOKS in /etc/mkinitcpio.conf
    sed -i -e "s/^HOOKS=.*/HOOKS=($MY_HOOKS)/" /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

set_bootctl() {
    local dev="$1"; shift

    bootctl install

    cat > /boot/loader/loader.conf <<EOF
timeout 3
default arch
editor 0
EOF

    arch_dev_uuid=$(blkid $dev | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p')

    cat > /boot/loader/entries/arch.conf <<EOF
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
EOF

    if [ -n "$CPU_MICROCODE" ]
    then
        sed -i -e "/initrd \/initramfs-linux.img/i initrd /$CPU_MICROCODE-ucode.img" /boot/loader/entries/arch.conf
    fi

    if [ -n "$ENC_DEV_NAME" ]
    then
        echo "options cryptdevice=UUID=$arch_dev_uuid:$ENC_DEV_NAME root=/dev/$LVM_GROUP/root quiet rw" >> /boot/loader/entries/arch.conf
    else
        echo "options root=/dev/$LVM_GROUP/root quiet rw" >> /boot/loader/entries/arch.conf
    fi
}

set_wired_network(){

    if [ -n "$PACKAGES_WM" ]
    then
        systemctl enable NetworkManager.service
    else
        local default_net_if=$(ip r | grep "default via" | cut -d " " -f 5)

        cat > /etc/systemd/network/20-wired.network <<EOF
[Match]
Name=$default_net_if

[Network]
DHCP=ipv4
EOF

        systemctl enable systemd-networkd.service
    fi
}

set_daemons() {

    systemctl enable sshd.service
}

set_sudoers() {
    sed -i -e 's/.*%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
}

set_root_password() {
    local password="$1"; shift

    echo -en "$password\n$password" | passwd
}

create_user() {
    local name="$1"; shift
    local password="$1"; shift

    useradd -m -s /bin/bash -G wheel,network,video,audio,optical,floppy,storage,scanner,power "$name"
    echo -en "$password\n$password" | passwd "$name"
}

###

clean() {
    local dev="/dev/$DRIVE"

    umount -R /mnt
    swapoff /dev/$LVM_GROUP/swap
    vgchange -an
    vgremove -y $LVM_GROUP
    if [ -n "$ENC_DEV_NAME" ]
    then
        cryptsetup luksClose /dev/mapper/$ENC_DEV_NAME
    fi

    parted -s "$dev" \
        rm 2 \
        rm 1 \
        mklabel gpt
}

###

headline() {
    echo -e "\n\n\e[1;34m#########################################"
    echo -e "#  \e[1;36m $1"
    echo -e "\e[1;34m#########################################\e[0m"
}


#
# Main
#
if [ "$1" == "chroot" ]
then
    configure
elif [ "$1" == "clean" ]
then
    clean
else
    setup
fi
