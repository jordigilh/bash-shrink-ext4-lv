# bash-shrink-ext4-lv
Shrinks a logical volume along with the ext4 file system contained in it using system tools. It uses the value defined with the key `x-systemd.shrinkfs` in the options field for the device entry in the `/etc/fstab` to shrink determine the new size. Example:

```
/dev/mapper/fedora-fedora /mnt ext4 defaults,x-systemd.shrinkfs=3G 1 2
```

In this case, the script will attempt to shrink the device in `/dev/mapper/fedora-fedora` to 3G, as defined by `x-systemd.shrinkfs=3G`.

Example:

```bash
$>./shrink.sh -d=/dev/mapper/fedora-fedora
fsck from util-linux 2.38-rc1
/dev/mapper/fedora-fedora: clean, 11/256000 files, 36966/1048576 blocks
resize2fs 1.46.5 (30-Dec-2021)
Resizing the filesystem on /dev/mapper/fedora-fedora to 786432 (4k) blocks.
The filesystem on /dev/mapper/fedora-fedora is now 786432 (4k) blocks long.

  Size of logical volume fedora/fedora changed from 4.00 GiB (1024 extents) to 3.00 GiB (768 extents).
  Logical volume fedora/fedora successfully resized.
```

## Dependencies
The script leverages on the following linux utilities:
* /usr/bin/numfmt: Bytes conversion.
* /usr/bin/findmnt: Determine if a device is mounted.
* /usr/bin/lsblk: Obtain the current device block size and the device name, when the UUID is provided.
* /usr/sbin/lvreduce: Reduce the logical volume and file system of the device.
* /usr/bin/awk: Extracting the UUID value from `/etc/fstab` to find the relative device name and retrieve the last line output by the `/usr/bin/df` command.
* /usr/sbin/blockdev: Determine the block size of the file system.
* /usr/sbin/fsck: Determine the amount of free blocks available in the file system.