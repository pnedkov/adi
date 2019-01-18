#!/bin/bash
set -e


#
# Setup
#
setup() {

    check_drive

    set_passwords

    partition_drive

    test -n "$LUKS_DEV_NAME" && encrypt_drive

    test -n "$LVM_GROUP" && setup_lvm

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

    test -n "$uefi" && set_bootctl || set_grub

    set_wired_network

    set_daemons

    set_sudoers

    set_root_password

    set_userland

    create_user

    rm -f /setup.sh
}

###

check_drive() {

    if ! [ -e $dev ]
    then
        echo -e "\nERROR: $dev does not exist!\n"
        exit 1
    fi

    local partitions=$(partprobe -d -s $dev | tail -c 2)
    if [[ "$partitions" =~ ^[0-9]+$ ]]
    then
        echo -e "\nERROR: $dev contains $partitions partition(s)"
        echo -e "Backup your data, delete all partitions on $dev and rerun the script\n"
        exit 1
    fi

}

set_passwords() {

    if [[ -n "$LUKS_DEV_NAME" && -z "$LUKS_PASSPHRASE" ]]
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

    if [ -n "$uefi" ]
    then
        parted -s "$dev" \
            mklabel gpt
    else
        parted -s "$dev" \
            mklabel msdos
    fi

    parted -s "$dev" \
        mkpart primary 0% 512M \
        mkpart primary 512M 100% \
        set 2 lvm on

    if [ -n "$uefi" ]
    then
        parted -s "$dev" \
            set 1 esp on
    else
        parted -s "$dev" \
            set 1 boot on
    fi
}

encrypt_drive() {

    headline "Encrypting partition"

    # GRUB does not support LUKS1
    test -n "$uefi" && luks_ver="luks2" || luks_ver="luks1"

    echo -en "$LUKS_PASSPHRASE" | cryptsetup --type $luks_ver --key-size 512 --hash sha512 luksFormat "$arch_dev"
    echo -en "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$arch_dev" "$LUKS_DEV_NAME"
}

setup_lvm() {

    headline "Setting up LVM"

    pvcreate -y "$lvm_pv"
    vgcreate -y "$LVM_GROUP" "$lvm_pv"

    if [ -n "$SWAP_SIZE" ]
    then
        lvcreate -y -L $SWAP_SIZE "$LVM_GROUP" -n swap
    fi

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

    if [ -n "$uefi" ]
    then
        mkfs.vfat -F32 $boot_dev
    else
        mkfs.$FS $boot_dev
    fi

    mkfs.$FS $root_dev

    if [ -e "$home_dev" ]
    then
        mkfs.$FS $home_dev
    fi

    if [ -n "$SWAP_SIZE" ]
    then
        mkswap $swap_dev
    fi
}

mount_filesystems() {

    headline "Mounting filesystems"

    mount $root_dev /mnt

    mkdir /mnt/boot
    mount $boot_dev /mnt/boot

    if [ -e "$home_dev" ]
    then
        mkdir /mnt/home
        mount $home_dev /mnt/home
    fi

    if [ -n "$SWAP_SIZE" ]
    then
        swapon $swap_dev
    fi
}

install_base() {

    headline "Installing base system"

    echo "Server = $MIRROR" > /etc/pacman.d/mirrorlist

    pacstrap /mnt base base-devel
    genfstab -U /mnt >> /mnt/etc/fstab
    cp -f /etc/resolv.conf /mnt/etc/resolv.conf
}

arch_chroot() {

    headline "Chrooting..."

    cp "$self" "/mnt/$(basename $self)"
    test -f "$conf" && cp "$conf" "/mnt/$(basename $conf)"

    # LVM workaround before chroot
    if [ -z "$uefi" ]
    then
        mkdir /mnt/hostlvm
        mount --bind /run/lvm /mnt/hostlvm
    fi

    arch-chroot /mnt /bin/bash -c "export ROOT_PASSWD=$ROOT_PASSWORD USER_PASSWD=$USER_PASSWORD; /$(basename $self) chroot"
}

unmount_filesystems() {

    headline "Unmounting filesystems"

    umount -R /mnt
    if [ -n "$SWAP_SIZE" ]
    then
        swapoff $swap_dev
    fi
    if [ -n "$LVM_GROUP" ]
    then
        vgchange -an
    fi
    if [ -n "$LUKS_DEV_NAME" ]
    then
        cryptsetup luksClose $luks_dev
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

    headline "Installing additional packages"

    local packages=''
    test -n "$CPU"               && packages+=" $CPU-ucode"
    test -n "$PACKAGES_BASE"     && packages+=" $PACKAGES_BASE"
    test -n "$PACKAGES_FONTS"    && packages+=" $PACKAGES_FONTS"
    test -n "$PACKAGES_X"        && packages+=" $PACKAGES_X"
    test -n "$PACKAGES_WM"       && packages+=" $PACKAGES_WM"
    test -n "$PACKAGES_USER_CLI" && packages+=" $PACKAGES_USER_CLI"
    test -n "$PACKAGES_USER_GUI" && packages+=" $PACKAGES_USER_GUI"
    test -z "$uefi"              && packages+=" grub"

    if [ -n "$VIDEO_DRIVER" ]
    then
        test "$VIDEO_DRIVER" == "nvidia" && packages+=" nvidia nvidia-utils nvidia-settings" || packages+=" xf86-video-$VIDEO_DRIVER"
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
127.0.0.1 localhost.localdomain localhost
::1       localhost.localdomain localhost

EOF

    local ip=$(ip r | grep "default via" | cut -d " " -f 3)
    local domain=$(grep -E "^domain " /etc/resolv.conf | cut -d " " -f 2)
    test -z "$domain" && domain=$(grep -E "^search " /etc/resolv.conf | cut -d " " -f 2)

    if [[ -n "$domain" ]]
    then
        echo "$ip $HOSTNAME.$domain $HOSTNAME" >> /etc/hosts
    else
        echo "$ip $HOSTNAME" >> /etc/hosts
    fi
}

set_timezone() {

    headline "Setting timezone"

    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

    hwclock --systohc
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
    sed -i -e "s/^MODULES=.*/MODULES=($FS)/" /etc/mkinitcpio.conf
    if [[ "$VIDEO_DRIVER" =~ ^(amdgpu|nvidia|nouveau|qlx)$ ]]
    then
        sed -i -e "s/^MODULES=(\(.*\))/MODULES=(\1 $VIDEO_DRIVER)/" /etc/mkinitcpio.conf
    fi

    # Set FILES in /etc/mkinitcpio.conf
    if [ "$VIDEO_DRIVER" == "nvidia" ]
    then
        sed -i -e "s#^FILES=.*#FILES=(/etc/modprobe.d/nvidia.conf)#" /etc/mkinitcpio.conf
    fi

    if [ -n "$LUKS_DEV_NAME" ]
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

    cat > /boot/loader/entries/arch.conf <<EOF
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
EOF

    if [ -n "$CPU" ]
    then
        sed -i -e "/initrd \/initramfs-linux.img/i initrd /$CPU-ucode.img" /boot/loader/entries/arch.conf
    fi

    if [ -n "$LUKS_DEV_NAME" ]
    then
        arch_dev_uuid=$(blkid $arch_dev | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p')
        echo "options cryptdevice=UUID=$arch_dev_uuid:$LUKS_DEV_NAME root=$root_dev quiet rw" >> /boot/loader/entries/arch.conf
    else
        echo "options root=$root_dev quiet rw" >> /boot/loader/entries/arch.conf
    fi
}

set_grub() {

    headline "Configuring GRUB"

    if [ "$VIDEO_DRIVER" == "nvidia" ]
    then
        sed -i -e "s#^GRUB_CMDLINE_LINUX_DEFAULT=.*#GRUB_CMDLINE_LINUX_DEFAULT=\"nvidia-drm.modeset=1\"#" /etc/default/grub
    fi

    if [ -n "$LUKS_DEV_NAME" ]
    then
        arch_dev_uuid=$(blkid $arch_dev | sed -n 's/.* UUID=\"\([^\"]*\)\".*/\1/p')
        sed -i -e "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$arch_dev_uuid:$LUKS_DEV_NAME root=$root_dev\"#" /etc/default/grub
        sed -i -e "s/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/" /etc/default/grub
    fi

    # LVM workaround
    ln -sf /hostlvm /run/lvm

    grub-install $dev

    grub-mkconfig -o /boot/grub/grub.cfg
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

    echo "root:$ROOT_PASSWD" | chpasswd
}

set_userland() {

    headline "Configuring userland"

    if [ "$VIDEO_DRIVER" == "nvidia" ]
    then
        cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
blacklist nouveau
EOF
    fi

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

    sed -i -e "s/^#Color/Color/" /etc/pacman.conf
    sed -i -e "s/^#TotalDownload/TotalDownload/" /etc/pacman.conf
    sed -i -e "s/^#VerbosePkgLists/VerbosePkgLists/" /etc/pacman.conf
    sed -i -e "/^VerbosePkgLists/aILoveCandy" /etc/pacman.conf

    sed -i -e "/^PS1=.*/d" /etc/skel/.bashrc
    echo -e "alias grep='grep --color=auto'\n" >> /etc/skel/.bashrc
    cp -f /etc/skel/.bashrc /root/
    cp -f /etc/skel/.bash_profile /root/
    echo 'export PS1="\[\033[38;5;12m\][\[$(tput sgr0)\]\[\033[38;5;9m\]\u\[$(tput sgr0)\]\[\033[38;5;12m\]@\[$(tput sgr0)\]\[\033[38;5;7m\]\h\[$(tput sgr0)\]\[\033[38;5;12m\]]\[$(tput sgr0)\]\[\033[38;5;15m\]: \[$(tput sgr0)\]\[\033[38;5;7m\]\w\[$(tput sgr0)\]\[\033[38;5;12m\]>\[$(tput sgr0)\]\[\033[38;5;9m\]\\$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"' >> /root/.bashrc
    echo 'export PS1="\[\033[38;5;12m\][\[$(tput sgr0)\]\[\033[38;5;10m\]\u\[$(tput sgr0)\]\[\033[38;5;12m\]@\[$(tput sgr0)\]\[\033[38;5;7m\]\h\[$(tput sgr0)\]\[\033[38;5;12m\]]\[$(tput sgr0)\]\[\033[38;5;15m\]: \[$(tput sgr0)\]\[\033[38;5;7m\]\w\[$(tput sgr0)\]\[\033[38;5;12m\]>\[$(tput sgr0)\]\[\033[38;5;10m\]\\$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"' >> /etc/skel/.bashrc
}

create_user() {

    if [ -n "$USER_NAME" ]
    then
        headline "Creating user $USER_NAME"

        useradd -m -s /bin/bash -G wheel,network,video,audio,optical,floppy,storage,scanner,power "$USER_NAME"
        echo "$USER_NAME:$USER_PASSWD" | chpasswd
    fi
}

###

clean() {

    umount -R /mnt
    if [ -n "$SWAP_SIZE" ]
    then
        swapoff $swap_dev
    fi

    if [ -n "$LVM_GROUP" ]
    then
        vgchange -an
        vgremove -y $LVM_GROUP
    fi

    if [ -n "$LUKS_DEV_NAME" ]
    then
        cryptsetup luksClose $luks_dev
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

password_prompt() {

    local msg="$1"; shift

    while true; do
        echo -n "$msg"
        stty -echo
        read password
        stty echo
        echo

        echo -n "Confirm password: "
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
self="$(readlink -f $0)"
conf="$(dirname $self)/$(basename $self .sh).conf"

# source the default conf file if exists
if [ -f "$conf" ]
then
    source "$conf"
else
    echo "ERROR: No such file: $conf"
    exit 1
fi

if [[ "$DRIVE" =~ ^(md|nvme) ]]
then
    part_prefix="p"
fi

# initialize all devices
dev="/dev/$DRIVE"
boot_dev="/dev/${DRIVE}${part_prefix}1"
arch_dev="/dev/${DRIVE}${part_prefix}2"

if [ -n "$LVM_GROUP" ]
then
    root_dev="/dev/$LVM_GROUP/root"
    swap_dev="/dev/$LVM_GROUP/swap"
    home_dev="/dev/$LVM_GROUP/home"
fi

lvm_pv="$arch_dev"

if [ -n "$LUKS_DEV_NAME" ]
then
    luks_dev="/dev/mapper/$LUKS_DEV_NAME"
    lvm_pv="$luks_dev"
fi


test -d /sys/firmware/efi && uefi=1

if [ "$1" == "chroot" ]
then
    configure
elif [ "$1" == "clean" ]
then
    clean
else
    setup
fi
