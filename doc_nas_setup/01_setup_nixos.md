# Partitioning

```bash
DISK1="/dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S6PYNL0Y211610F"
DISK2="/dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S6PYNL0Y211413X"
```

```bash
sgdisk --zap-all $DISK1
sgdisk --new=1:0:+1G --typecode=1:EF00 --change-name=1:"EFI System" $DISK1
sgdisk --new=2:0:-64G --typecode=2:BF00 --change-name=2:"ZFS System" $DISK1
sgdisk --new=3:0:0 --typecode=3:8200 --change-name=3:"Swap" $DISK1

# Verify partitions
sgdisk --print $DISK1
```

(repeat same for DISK2)

ZFS_PART1="$DISK1-part2" # e.g., /dev/disk/by-id/ata-XYZ-part2
ZFS_PART2="$DISK2-part2" # e.g., /dev/disk/by-id/ata-ABC-part2

```bash
zpool create -o ashift=12 -o autotrim=on -O acltype=posixacl -O canmount=off -O compression=lz4 -O dnodesize=auto -O normalization=formD -O relatime=on -O xattr=sa -O mountpoint=none -R /mnt rpool mirror $ZFS_PART1 $ZFS_PART2
```

```bash
zfs create -o canmount=noauto -o mountpoint=legacy rpool/root
zfs create -o mountpoint=legacy rpool/nix
zfs create -o mountpoint=legacy rpool/home
zfs create -o mountpoint=legacy rpool/var

mkdir -p /mnt/root
mount -t zfs rpool/root /mnt

mkdir -p /mnt/nix
mkdir -p /mnt/home
mkdir -p /mnt/var

mount -t zfs rpool/nix /mnt/nix
mount -t zfs rpool/home /mnt/home
mount -t zfs rpool/var /mnt/var
```

## Boot partition

```bash
EFI_PART1="$DISK1-part1" # e.g., /dev/disk/by-id/ata-XYZ-part1

mkfs.vfat -F 32 -n EFI $EFI_PART1
mkdir -p /mnt/boot
mount $EFI_PART1 /mnt/boot
```

## Swap

```bash
SWAP_PART1="$DISK1-part3" # e.g., /dev/disk/by-id/ata-XYZ-part3
SWAP_PART2="$DISK2-part3" # e.g., /dev/disk/by-id/ata-ABC-part3

mkswap -L swap1 $SWAP_PART1
mkswap -L swap2 $SWAP_PART2

swapon $SWAP_PART1
swapon $SWAP_PART2
```

# ZFS

```bash
zpool status
```


# HDD Setup

## Burn-in / initial check

Don't forget to use tmux...

```bash
nix-shell -p smartmontools badblocks fio
lsblk -d -o NAME,MODEL,SERIAL,SIZE
```

- simple PASSED / FAILED
```
sudo smartctl -i /dev/sdX
```

- details 
```
sudo smartctl -A /dev/sdX
```

check RAW_VALUES being ZERO:
- Reallocated_Sector_Ct
- Current_Pending_Sector
- Offline_Uncorrectable
- Seek_Error_Rate

- long self-test
```
sudo smartctl -t long /dev/sdX
```

- destructive burn-in (might take several hours / days)
```
sudo badblocks -b 4096 -wsv /dev/sdX
```

- final check
```
sudo smartctl -A /dev/sdX
```



Summary of Process
For each drive:

- Initial S.M.A.R.T. Check: `smartctl -H -A /dev/sdX`. Look for PASSED and zero error attributes.
- S.M.A.R.T. Long Test: `smartctl -t long /dev/sdX`. Wait for it to complete without errors.
- Destructive Surface Scan: `badblocks -wsv /dev/sdX`. Wait for it to complete with 0 errors.
- Final S.M.A.R.T. Check: `smartctl -A /dev/sdX`. Ensure Reallocated_Sector_Ct is still zero.


# NixOS configuration

```bash
nixos-generate-config --root /mnt
nix-env -f '<nixpkgs>' -iA bat
nix-env -f '<nixpkgs>' -iA vim
vim /mnt/etc/nixos/configuration.nix

```

Changes:
```bash
nixos-rebuild swtich
```



Changes:
```bash
nixos-rebuild swtich
```




# zpool data
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -m /data/lake \
    lake \
    raidz2 \
      /dev/disk/by-id/ata-ST8000NT001-3LZ101_WWZ8Q357 \
      /dev/disk/by-id/ata-ST8000NT001-3LZ101_WWZ8Q378 \
      /dev/disk/by-id/ata-ST8000NT001-3LZ101_WWZ8Q3EN \
      /dev/disk/by-id/ata-ST8000NT001-3LZ101_WWZ8Q3QB \
    special mirror \
      /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_4TB_S7DPNF0Y327165B \
      /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_with_Heatsink_4TB_S7DSNJ0Y203121H

zfs set compression=lz4 lake

zfs create lake/media
zfs create lake/documents
zfs create lake/photos
zfs create lake/backups

# Photo thumbnails and many JPEGs are < 1MB
zfs set special_small_blocks=512K lake
zfs set special_small_blocks=1M lake/photos
zfs set special_small_blocks=0 lake/media
zfs set special_small_blocks=0 lake/backups


zpool list -v lake