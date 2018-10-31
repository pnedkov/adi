# Arch Direct Installer

ADI is a shell script for installing Arch Linux. It requires minimal initial configuration and can be completely non-interactive.

### Disk layout

```
+---------------------+------------------------+------------------------+-------------------------------+
|                     |                        |                        |                               |
|   Boot partition    |  Logical volume 1      |  Logical volume 2      |  Logical volume 3 (optional)  |
|                     |                        |                        |                               |
|   /boot             |  SWAP                  |  /                     |  /home                        |
|                     |                        |                        |                               |
|                     |  /dev/$LVM_GROUP/swap  |  /dev/$LVM_GROUP/root  |  /dev/$LVM_GROUP/home         |
|                     |                        |                        |                               |
|   512MB             |  $SWAP_SIZE            |  $ROOT_SIZE            |  SIZE = sda1 - swap - root    |
|                     |                        |                        |                               |
|   File system:      |                        |  File system = $FS     |  File system = $FS            |
|                     |                        |                        |                               |
|      BIOS: $FS      +------------------------+------------------------+-------------------------------+
|                     |                                                                                 |
|      UEFI: FAT32    |                     LUKS encrypted partition (optional)                         |
|                     |                                                                                 |
|                     |                     /dev/mapper/$LUKS_DEV_NAME                                  |
|                     |                                                                                 |
+---------------------+---------------------------------------------------------------------------------+
|                     |                                                                                 |
|       /dev/sda1     |                                 /dev/sda2                                       |
|                     |                                                                                 |
+---------------------+---------------------------------------------------------------------------------+
|                                                                                                       |
|                                     /dev/sda - $DRIVE - msdos (BIOS) or gpt (UEFI)                    |
|                                                                                                       |
+-------------------------------------------------------------------------------------------------------+

```

### Prerequisites:
 * Backup!
 * The disk where Arch Linux will be installed should not contain any partitions


### Features
 * Completely non-interactive Arch Linux installation:
    * by directly editing the variables in adi.sh
    * by deploying adi.conf in the same directory as adi.sh containing all variables you want customized
 * Install on a legacy BIOS and UEFI systems
 * Install on mdadm software RAID devices but you have to set it up first
 * Encrypt the whole second partition on $DRIVE where /, /home*(optional)* and swap reside
 * User defined file system: ext4/xfs
 * User defined size for /, /home and swap
 * User defined lists of packages that will be installed

### Limitations
 * Preserve any data on $DRIVE
 * Install on a drive with existing partitions
 * Perform sophisticated setup configuration with custom disk layout

### Installation instructions
1. Boot from the official Arch Linux iso
2. ```pacman -Sy git```
3. ```git clone https://github.com/pnedkov/adi.git```
4. ```cd adi/```
5. Edit the variables in adi.sh *or* deploy your own adi.conf
6. ```./adi.sh```
