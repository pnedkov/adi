#!/bin/bash
set -e

# Drive to install to
DRIVE='sda'

# File system for / and /home: xfs/ext4
FS='xfs'

# LVM group name
LVM_GROUP='archvg'

# Size of swap LV
SWAP_SIZE='2G'

# Size of root LV (leave blank for 100%FREE and no separate /home LV)
ROOT_SIZE='16G'

# Encrypted device (leave blank to disable LUKS encryption)
ENC_DEV_NAME='cryptlvm'

# LUKS passphrase (leave blank to be prompted)
LUKS_PASSPHRASE='apasswd'

# Hostname
HOSTNAME='archy'

# Root password (leave blank to be prompted)
ROOT_PASSWORD='bpasswd'

# Main user member of wheel group (leave blank to disable user creation)
USER_NAME='plamen'

# The main user's password (leave blank to be prompted)
USER_PASSWORD='cpasswd'

# System timezone
TIMEZONE='America/Los_Angeles'

# System keymap: us/dvorak
KEYMAP='us'

# Video driver: amdgpu/ati/dummy/fbdev/intel/nouveau/nvidia/vesa/vmware/voodoo/qxl or blank
VIDEO_DRIVER=''

# Packages CLI (comment to disable)
PACKAGES_BASE='net-tools ntp openssh sudo wget vim bash-completion'
PACKAGES_FONTS='terminus-font ttf-hack ttf-anonymous-pro ttf-dejavu ttf-freefont ttf-liberation'
PACKAGES_USER_CLI='htop netcat alsa-utils'

# Packages GUI
#PACKAGES_X='xorg-server xorg-apps xorg-xinit xterm'

# KDE full
#PACKAGES_WM='plasma-meta kde-applications-meta kde-gtk-config'
# KDE base
#PACKAGES_WM='plasma-desktop plasma-nm plasma-pa kde-gtk-config sddm-kcm kdebase-meta kdegraphics-meta kdenetwork-meta kdeutils-meta'
# Xfce
#PACKAGES_WM='xfce4 xfce4-goodies'

#PACKAGES_USER_GUI='terminator chromium'


#
# Setup
#
setup() {

    set_passwords

    partition_drive

    if [ -n "$ENC_DEV_NAME" ]
    then
        local lvm_pv="/dev/mapper/$ENC_DEV_NAME"
        encrypt_drive
    else
        local lvm_pv="$arch_dev"
    fi

    setup_lvm

    format_filesystems

    mount_filesystems

    install_base

    arch_chroot

    if [ -f /mnt/setup.sh ]
    then
        echo -e "\n\n\e[1;31m ERROR: Script failed, not unmounting filesystems so you can investigate.\e[0m"
        echo "Make sure you run \'$0 clean\' before you run this script again."
    else
        unmount_filesystems

        echo -e "\n\n\e[1;32m Done! Reboot system.\e[0m\n"
    fi
}


#
# Configure
#
configure() {

    detect_cpu

    install_packages

    clean_packages

    set_hostname

    set_hosts

    set_timezone

    set_locale

    set_vconsole

    set_initcpio

    set_bootctl

    set_wired_network

    set_daemons

    set_sudoers

    set_root_password

    create_user

    set_userland

    rm -f /setup.sh
}

###

set_passwords() {

    if [ -z "$LUKS_PASSPHRASE" ]
    then
        headline "LUKS passphrase"
        password_prompt "Enter a passphrase to encrypt $arch_dev: "
        LUKS_PASSPHRASE="$password"
    fi

    if [ -z "$ROOT_PASSWORD" ]
    then
        headline "Root password"
        password_prompt "Enter the root password: "
        ROOT_PASSWORD="$password"
    fi

    if [[ -n "$USER_NAME" && -z "$USER_PASSWORD" ]]
    then
        headline "User password"
        password_prompt "Enter the password for user $USER_NAME: "
        USER_PASSWORD="$password"
    fi
}

partition_drive() {

    headline "Creating partitions"

    parted -s "/dev/$DRIVE" \
        mklabel gpt \
        mkpart primary 0% 512M \
        set 1 esp on \
        mkpart primary 512M 100% \
        set 2 lvm on
}

encrypt_drive() {

    headline "Encrypting partition"

    echo -en "$LUKS_PASSPHRASE" | cryptsetup luksFormat "$arch_dev"
    echo -en "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$arch_dev" "$ENC_DEV_NAME"
}

setup_lvm() {

    headline "Setting up LVM"

    pvcreate -y "$lvm_pv"
    vgcreate -y "$LVM_GROUP" "$lvm_pv"

    lvcreate -y -L $SWAP_SIZE "$LVM_GROUP" -n swap

    if [ -n "$ROOT_SIZE" ]
    then
        lvcreate -y -L $ROOT_SIZE "$LVM_GROUP" -n root
        lvcreate -y -l 100%FREE "$LVM_GROUP" -n home
    else
        lvcreate -y -l 100%FREE "$LVM_GROUP" -n root
    fi

    #vgchange -ay
}

format_filesystems() {

    headline "Formatting filesystems"

    mkfs.vfat -F32 $boot_dev

    mkfs.$FS /dev/$LVM_GROUP/root

    if [ -e /dev/$LVM_GROUP/home ]
    then
        mkfs.$FS /dev/$LVM_GROUP/home
    fi

    mkswap /dev/$LVM_GROUP/swap
}

mount_filesystems() {

    headline "Mounting filesystems"

    mount /dev/$LVM_GROUP/root /mnt

    mkdir /mnt/boot
    mount "$boot_dev" /mnt/boot

    if [ -e /dev/$LVM_GROUP/home ]
    then
        mkdir /mnt/home
        mount /dev/$LVM_GROUP/home /mnt/home
    fi

    swapon /dev/$LVM_GROUP/swap
}

install_base() {

    headline "Installing base system"

    echo 'Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist

    pacstrap /mnt base base-devel
    genfstab /mnt >> /mnt/etc/fstab
    cp -f /etc/resolv.conf /mnt/etc/resolv.conf
}

arch_chroot() {

    headline "Chrooting..."

    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot
}

unmount_filesystems() {

    headline "Unmounting filesystems"

    umount -R /mnt
    swapoff /dev/$LVM_GROUP/swap
    vgchange -an
    if [ -n "$ENC_DEV_NAME" ]
    then
        cryptsetup luksClose /dev/mapper/$ENC_DEV_NAME
    fi
}

###

detect_cpu() {

    if $(lscpu | grep -q "GenuineIntel")
    then
        CPU="intel"
    elif $(lscpu | grep -q "AuthenticAMD")
    then
        CPU="amd"
    else
        CPU=""
    fi
}


install_packages() {
    local packages=''

    headline "Installing additional packages"

    # CPU microcode
    if [ -n "$CPU" ]
    then
        packages+=" $CPU-ucode"
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

    if [ -n "$VIDEO_DRIVER" ]
    then
        if [ "$VIDEO_DRIVER" == "nvidia" ]
        then
            packages+=" nvidia nvidia-utils nvidia-settings"

            cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
blacklist nouveau
EOF
        else
            packages+=" xf86-video-$VIDEO_DRIVER"
        fi
    fi

    pacman -Sy --noconfirm $packages
}

clean_packages() {

    headline "Clearing package tarballs"

    yes | pacman -Scc
}

set_hostname() {

    headline "Setting hostname"

    echo "$HOSTNAME" > /etc/hostname
}

set_hosts() {

    headline "Setting hosts file"

    cat > /etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost $HOSTNAME
::1       localhost.localdomain localhost $HOSTNAME
EOF
}

set_timezone() {

    headline "Setting timezone"

    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

set_locale() {

    headline "Setting locale"

    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    locale > /etc/locale.conf
}

set_vconsole() {

    headline "Configuring keyboard in console"

    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "FONT=ter-g16n" >> /etc/vconsole.conf
}

set_initcpio() {

    headline "Configuring initial ramdisk"

    # Set MODULES in /etc/mkinitcpio.conf
    sed -i -e "s/^MODULES=.*/MODULES=\"$FS\"/" /etc/mkinitcpio.conf
    if [[ "$VIDEO_DRIVER" =~ ^(amdgpu|nvidia|nouveau|qlx)$ ]]
    then
        sed -e "s/^MODULES=\"\(.*\)\"/MODULES=\"\1 $VIDEO_DRIVER\"/" /etc/mkinitcpio.conf
    fi

    # Set FILES in /etc/mkinitcpio.conf
    if [ "$VIDEO_DRIVER" == "nvidia" ]
    then
        sed -i -e "s/^FILES=.*/FILES=\"/etc/modprobe.d/nvidia.conf\"/" /etc/modprobe.d/nvidia.conf
    fi

    if [ -n "$ENC_DEV_NAME" ]
    then
        MY_HOOKS="base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck"
    else
        MY_HOOKS="base udev autodetect keyboard keymap consolefont modconf block lvm2 filesystems fsck"
    fi

    # Set HOOKS in /etc/mkinitcpio.conf
    sed -i -e "s/^HOOKS=.*/HOOKS=($MY_HOOKS)/" /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

set_bootctl() {

    headline "Configuring UEFI boot"

    bootctl install

    cat > /boot/loader/loader.conf <<EOF
timeout 3
default arch
editor 0
EOF

    arch_dev_uuid=$(blkid $arch_dev | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p')

    cat > /boot/loader/entries/arch.conf <<EOF
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
EOF

    if [ -n "$CPU" ]
    then
        sed -i -e "/initrd \/initramfs-linux.img/i initrd /$CPU-ucode.img" /boot/loader/entries/arch.conf
    fi

    if [ -n "$ENC_DEV_NAME" ]
    then
        echo "options cryptdevice=UUID=$arch_dev_uuid:$ENC_DEV_NAME root=/dev/$LVM_GROUP/root quiet rw" >> /boot/loader/entries/arch.conf
    else
        echo "options root=/dev/$LVM_GROUP/root quiet rw" >> /boot/loader/entries/arch.conf
    fi
}

set_wired_network(){

    headline "Configuring netowrk"

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

    headline "Setting initial daemons"

    systemctl enable sshd.service

    if [ -n "$PACKAGES_WM" ]
    then
        systemctl enable sddm.service
    fi
}

set_sudoers() {

    headline "Configuring sudo"

    sed -i -e 's/.*%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
}

set_root_password() {

    headline "Setting root password"

    echo "root:$ROOT_PASSWORD" | chpasswd
}

create_user() {

    if [ -n "$USER_NAME" ]
    then
        headline "Creating user $USER_NAME"

        useradd -m -s /bin/bash -G wheel,network,video,audio,optical,floppy,storage,scanner,power "$USER_NAME"
        echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    fi
}

set_userland() {

    headline "Configuring userland"

    if [ -n "$PACKAGES_WM" ]
    then
        cat > /etc/sddm.conf <<EOF
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=
RebootCommand=

[Theme]
Current=breeze
CursorTheme=breeze_cursors

[Users]
MaximumUid=65000
MinimumUid=1000
EOF
    fi
}

###

clean() {

    umount -R /mnt
    swapoff /dev/$LVM_GROUP/swap
    vgchange -an
    vgremove -y $LVM_GROUP
    if [ -n "$ENC_DEV_NAME" ]
    then
        cryptsetup luksClose /dev/mapper/$ENC_DEV_NAME
    fi

    parted -s "/dev/$DRIVE" \
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

password_prompt() {
    local msg="$1"; shift

    while true; do
        echo -n "$msg"
        stty -echo
        read password
        stty echo
        echo

        echo -n "Password again: "
        stty -echo
        read password2
        stty echo
        echo

        if [ -z "$password" ]
        then
            echo "Password cannot be empty. Try again."
        elif [ "$password" != "$password2" ]
        then
            echo "Passwords do not match. Try again."
        else
            break
        fi
    done
}


#
# Main
#
boot_dev="/dev/${DRIVE}1"
arch_dev="/dev/${DRIVE}2"

# source adi.conf if exists
conf="$(dirname $(readlink -f "$0"))/adi.conf"
if [ -f "$conf" ]
then
    source "$conf"
fi

if [ "$1" == "chroot" ]
then
    configure
elif [ "$1" == "clean" ]
then
    clean
else
    setup
fi
