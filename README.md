# Arch Direct Installer

ADI is a shell script for installing Arch Linux. It requires minimal initial configuration and can be completely non-interactive.

This installation script is intended to suit only my needs. I borrowed some ideas from other Arch Linux installation scripts here on github.com.

### Disk layout

```
+----------------+----------------------+----------------------+---------------------------------------+
|                |                      |                      |                                       |
| Boot partition | Logical volume 1     | Logical volume 2     | Logical volume 3                      |
|                | (optional)           |                      | (optional)                            |
|                |                      |                      |                                       |
| /dev/sda1      | /dev/$LVM_GROUP/swap | /dev/$LVM_GROUP/root | /dev/$LVM_GROUP/home                  |
|                |                      |                      |                                       |
| 512MB          | $SWAP_SIZE           | $ROOT_SIZE           | SIZE = sda2 - $SWAP_SIZE - $ROOT_SIZE |
|                |                      |                      |                                       |
| Mount: /boot   |                      | Mount: /             | Mount: /home                          |
|                |                      |                      |                                       |
| File system:   |                      | File system = $FS    | File system = $FS                     |
|                |                      |                      |                                       |
|  BIOS: $FS     +----------------------+----------------------+---------------------------------------+
|                |                                                                                     |
|  UEFI: FAT32   |                       LUKS encrypted partition (optional)                           |
|                |                                                                                     |
|                |                       /dev/mapper/$LUKS_DEV_NAME                                    |
|                |                                                                                     |
+----------------+-------------------------------------------------------------------------------------+
|                |                                                                                     |
|   /dev/sda1    |                                /dev/sda2                                            |
|                |                                                                                     |
+----------------+-------------------------------------------------------------------------------------+
|                                                                                                      |
|                              /dev/sda - $DRIVE : msdos (BIOS) or gpt (UEFI)                          |
|                                                                                                      |
+------------------------------------------------------------------------------------------------------+
```

### Prerequisites:
 * Backup!
 * The disk where Arch Linux will be installed should not contain any partitions

### Features
 * Completely non-interactive Arch Linux installation:
    * by directly editing the variables in adi.sh
    * by deploying adi.conf in the same directory as adi.sh containing all variables you want customized
 * Install on a legacy BIOS and UEFI systems
 * Install on a mdadm software RAID device but you have to create it first
 * No other storage device than $DRIVE will be altered
 * Encrypt the whole second partition on $DRIVE where /, /home*(optional)* and swap*(optional)* reside
 * User defined file system: ext4/xfs
 * User defined size for /, /home and swap
 * User defined lists of packages that will be installed

### Limitations
 * Cannot preserve any data on $DRIVE
 * Cannot install on a drive with existing partitions
 * Cannot perform sophisticated setup configuration with custom disk layout

### Installation instructions
1. Boot from the official Arch Linux iso
2. Configure Internet connection
3. ```pacman -Sy git```
4. ```git clone https://github.com/pnedkov/adi.git```
5. ```cd adi/```
6. Edit the variables in adi.sh *or* deploy your own adi.conf
7. ```./adi.sh```
