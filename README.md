# bash-shrink-ext4-lv
Shrinks a logical volume along with the ext4 file system contained in it using system tools. It uses the value defined with the key `x-systemd.shrinkfs` in the options field for the device entry in the `/etc/fstab` to shrink determine the new size. Example:

```
/dev/mapper/fedora-fedora /mnt ext4 defaults,x-systemd.shrinkfs=3G 1 2
```

In this case, the script will attempt to shrink the device in `/dev/mapper/fedora-fedora` to 3G, as defined by `x-systemd.shrinkfs=3G`.

Example:

```bash
[root@localhost ~]# ./shrink.sh -d=/dev/mapper/rhel-home
fsck from util-linux 2.23.2
/dev/mapper/rhel-home: 11/1175040 files (0.0% non-contiguous), 117810/4718592 blocks
resize2fs 1.42.9 (28-Dec-2013)
The filesystem is already 4718592 blocks long.  Nothing to do!

  Size of logical volume rhel/home changed from 20.01 GiB (5123 extents) to 18.00 GiB (4608 extents).
  Logical volume rhel/home successfully resized.
[root@localhost ~]# ./shrink.sh -d=/dev/mapper/rhel-home
Current volume size for device /dev/mapper/rhel-home already equals 19327352832 bytes
```

## Dependencies
The script leverages on the following linux utilities:
* /usr/bin/numfmt: Bytes conversion.
* /usr/bin/findmnt: Determine if a device is mounted.
* /usr/bin/lsblk: Obtain the current device block size and the device name, when the UUID is provided.
* /usr/sbin/lvm: Reduce the logical volume and file system of the device.
* /usr/bin/awk: Extracting the UUID value from `/etc/fstab` to find the relative device name and retrieve the last line output by the `/usr/bin/df` command.
* /usr/sbin/tune2fs: Determine the number of blocks in the device. Use this number to calculate if the device is capable of shrinking to the expected size.
* /usr/sbin/resize2fs: Determine an estimated maximum free block size of the file system.
* /usr/bin/cut: extract the UUID from the /etc/fstab entry