# Arch Direct Installer

ADI is a shell script for installing Arch Linux. It requires minimal initial configuration and can be completely unattended.

This installation script is intended to suit only my needs. I borrowed some ideas from other Arch Linux install scripts here on github.com.

## Disk layout

### LVM
```
+----------------+----------------------+----------------------+---------------------------------------+
|                |                      |                      |                                       |
| Boot           | Logical volume 1     | Logical volume 2     | Logical volume 3                      |
|                | (optional)           |                      | (optional)                            |
|                |                      |                      |                                       |
| /dev/sda1      | /dev/$LVM_GROUP/swap | /dev/$LVM_GROUP/root | /dev/$LVM_GROUP/home                  |
|                |                      |                      |                                       |
| $BOOT_SIZE     | $SWAP_SIZE           | $ROOT_SIZE           | Size depends on $ROOT_SIZE            |
|                |                      |                      |                                       |
| /boot          |                      | /                    | /home                                 |
|                |                      |                      |                                       |
| BIOS: $FS      |                      | $FS                  | $FS                                   |
|                |                      |                      |                                       |
| UEFI: FAT32    +----------------------+----------------------+---------------------------------------+
|                |                                                                                     |
|                |                        LUKS encrypted partition                                     |
|                |                       /dev/mapper/$LUKS_DEV_NAME                                    |
|                |                              (optional)                                             |
|                |                                                                                     |
+----------------+-------------------------------------------------------------------------------------+
|                |                                                                                     |
| dev/${DRIVE}1  |                             /dev/${DRIVE}2                                          |
|                |                                                                                     |
+----------------+-------------------------------------------------------------------------------------+
|                                                                                                      |
|                                    /dev/$DRIVE : msdos (BIOS) or gpt (UEFI)                          |
|                                                                                                      |
+------------------------------------------------------------------------------------------------------+
```

### Standard partitions
```
+----------------+--------------------+----------------------------+-----------------------------------+
|                |                    |                            |                                   |
|  Boot          |  Swap              |  Root                      |  Home                             |
|  (optional)    |  (optional)        |                            |  (optional)                       |
|                |                    |                            |                                   |
|  $BOOT_SIZE    |  $SWAP_SIZE        |  $ROOT_SIZE                |  Size depends on $ROOT_SIZE       |
|                |                    |                            |                                   |
|  /boot         |                    |  /                         |  /home                            |
|                |                    |                            |                                   |
|  BIOS: $FS     |                    |  $FS                       |  $FS                              |
|                |                    |                            |                                   |
|  UEFI: FAT32   |                    |                            |                                   |
|                |                    |                            |                                   |
|                |                    |                            |                                   |
|                |                    |                            |                                   |
|                |                    +----------------------------+                                   |
|                |                    |                            |                                   |
|                |                    | /dev/mapper/$LUKS_DEV_NAME |                                   |
|                |                    |        (optional)          |                                   |
+----------------+--------------------+----------------------------+-----------------------------------+
|                |                    |                            |                                   |
| /dev/${DRIVE}1 | /dev/${DRIVE}[1,2] |   /dev/${DRIVE}[1,2,3]     |       /dev/${DRIVE}[2,3,4]        |
|                |                    |                            |                                   |
+----------------+--------------------+----------------------------+-----------------------------------+
|                                                                                                      |
|                                    /dev/$DRIVE : msdos (BIOS) or gpt (UEFI)                          |
|                                                                                                      |
+------------------------------------------------------------------------------------------------------+
```

## Prerequisites:
 * Backup!
 * The disk where Arch Linux will be installed should not contain any partitions

## Features
 * Completely unattended Arch Linux installation
 * Install on a legacy BIOS and UEFI systems
 * Install on LVM or standard partitions
 * Install on a mdadm software RAID device but you have to create it first
 * LUKS with LVM: Encrypt the second partition on top of which the LVM Physical Volume is created
 * LUKS with partitions: Encrypt the root but not the home partition
 * No storage device other than $DRIVE will be altered
 * Different disk layouts depending on the configuration
 * User defined size for boot, swap, root and home
 * User defined file system for boot, root and home: ext4/xfs
 * User defined lists of packages separated in different categories

## Limitations
 * Cannot preserve any data on $DRIVE
 * Cannot install on a drive with existing partitions
 * Cannot perform sophisticated setup configuration with custom disk layout
 * Cannot encrypt the /home partition

## Installation instructions
1. Boot from the official Arch Linux iso
2. Configure Internet connection
3. ```pacman -Sy git```
4. ```git clone https://github.com/pnedkov/adi.git```
5. ```cd adi/```
6. ```cp sample.adi.conf adi.conf``` and edit the configuration file
7. ```./adi.sh```
