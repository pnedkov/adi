# Arch Direct Installer

ADI is a shell script for installing Arch Linux. It requires minimal initial configuration and can be completely non-interactive.

### Structure

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
+-------------------------------------------------------------------------------------------------------+
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


### What ADI can do:
 * Completely non-interactive Arch Linux installation
 * Install on a legacy BIOS and UEFI systems
 * Encrypt the partition where /, /home and swap reside
 * Support user defined file system: ext4/xfs
 * Support user defined size for /, /home and swap
 * Support user defined lists of packages that will be installed


### What ADI cannot do:
 * Install on a drive with existing partitions
 * Preserve your /home
 * Perform sophisticated setup configuration
 * Find you a girlfriend
 * Make America Great Again
