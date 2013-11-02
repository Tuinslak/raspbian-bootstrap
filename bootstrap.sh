#!/bin/bash

# v1:
# Based on work by Klaus M Pfeiffer at http://blog.kmp.or.at/2012/05/build-your-own-raspberry-pi-image/
# you need to do: "sudo apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools"
# run with "sudo bootstrap.sh /dev/sd[x]"

# v2:
# Based on work by Alexandre Bulte at https://gist.github.com/abulte/3917357

# v3:
# Jun 2013
# Yeri Tiete (http://yeri.be)
# > Made sure it bootstrapped again correctly.
# and some other changes
# Repo can be found on Github: http://yeri.be/11v
# More updates followed in July, August
# v3.1:
# Nov 2013
# Use of additional files, fixed some other issues.
# Support for 2Gb SD cards and resizefs at firstboot.

echo "> Use like: sudo bootstrap.sh /dev/sd[x]"

# variables... Might want to change some stuff here.
buildenv="/root/raspbian/bootstrap"
rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"
deb_local_mirror="http://mirrordirector.raspbian.org/raspbian"
bootsize="128M"
# set rootsize to 1,6Gb. This way, we'll be able to flash 2Gb and up SD cards.
# We'll run resize2fs later to make sure it uses the entire disk.
rootsize="1624M"
deb_release="wheezy"
device=$1
mydate=`date +%Y%m%d`
image=""
# set your local domain name
DOMAIN=botnet.corp.flatturtle.com
# configure which packages to install.
source ./packages.sh
# Keymap to use (this seems to provide a decent list: http://nic.phys.ethz.ch/projects/dphys3/planning/debconf.final)
# note: this doesn't really seem to work (check further down in the script and alter /etc/default/keyboard part)
KEYMAP="console-data/keymap/azerty/belgian/standard/keymap"


#
####### START OF MESSY CODE
#


if [ $EUID -ne 0 ]; then
  echo "ERROR: This tool must be run as root"
  exit 1
fi

if ! [ -b $device ]; then
  echo "ERROR: Device $device is not a block device"
  exit 1
fi

if [ "$device" == "" ]; then
  echo "WARNING: No block device given, creating image instead."
  mkdir -p $buildenv
  image="${buildenv}/rpi_basic_${deb_release}_${mydate}.img"
  dd if=/dev/zero of=$image bs=1MB count=1000
  device=`losetup -f --show $image`
  echo "Image $image Created and mounted as $device"
else
  dd if=/dev/zero of=$device bs=512 count=1
fi

fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2

+$rootsize
w
EOF


if [ "$image" != "" ]; then
  losetup -d $device
  device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  echo "--- kpartx device ${device}"
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
  echo "--- rootp ${rootp}"
  echo "--- bootp ${bootp}"
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "ERROR: Can't find boot partition, neither as ${device}1, nor as ${device}p1. Exiting."
      exit 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi
fi

mkfs.vfat $bootp
mkfs.ext4 $rootp

mkdir -p $rootfs


mount $rootp $rootfs

cd $rootfs

echo "--- debootstrap --no-check-gpg --foreign --arch=armhf  --variant=minbase ${deb_release} ${rootfs} ${deb_local_mirror}"
debootstrap --no-check-gpg --foreign --arch=armhf --variant=minbase $deb_release $rootfs $deb_local_mirror
echo "debootstrap ok"

cp /usr/bin/qemu-arm-static usr/bin/

echo "=> executing second-stage (debootstrap)."

LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

mount $bootp $bootfs

# prevent LOCALE errors
export LANGUAGE=C
export LANG=C
export LC_ALL=C

# This should match what has been written above. Couldn't use variables in my test; they got cleared for some reason.
echo "deb $deb_local_mirror wheezy main" > etc/apt/sources.list
echo "deb-src $deb_local_mirror wheezy main" >> etc/apt/sources.list

# get the raspbian key, or you'll get untrusted package errors
wget http://archive.raspbian.org/raspbian.public.key -O ./raspbian.key

echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

# make fstab file
echo "# /etc/fstab: static file system information.
# <file system>  <dir> <type> <options>             <dump> <pass>

# System mounts
proc            /proc   proc  defaults                  0   0

# Data mounts
/dev/mmcblk0p1  /boot   vfat  defaults                  0   0
/dev/mmcblk0p2  /       ext4  noatime,errors=remount-ro 0   1

# Minimize writes
tmpfs           /var/log            tmpfs defaults,noatime 0 0
tmpfs           /var/cache/apt      tmpfs defaults,noatime 0 0
tmpfs           /var/lib/apt/lists  tmpfs defaults,noatime 0 0
" > etc/fstab

# give it a name
echo "bootstrappi" > etc/hostname

# create network file
echo "auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
" > etc/network/interfaces

echo "vchiq
snd_bcm2835
" >> etc/modules

echo "console-common  console-data/keymap/policy  select  Select keymap from full list
console-common  console-data/keymap/full  select  $KEYMAP
" > debconf.set

# This should be changed probably.
echo "# KEYBOARD CONFIGURATION FILE
# Consult the keyboard(5) manual page.
XKBMODEL=\"pc105\"
XKBLAYOUT=\"be\"
XKBVARIANT=\"\"
XKBOPTIONS=\"\"
BACKSPACE=\"guess\"
" > etc/default/keyboard

echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-key add raspbian.key
rm -f raspbian.key
apt-get update
apt-get -y install $PACKAGES
wget http://goo.gl/1BOfJ -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
touch /boot/start.elf
mkdir -p /lib/modules
rpi-update
# remove backups and other crap
rm -rf /boot.bak
rm -rf /lib/modules.bak
# set root psw to raspberry
echo root:raspberry | chpasswd
# The other keymap thing is not working. This forces be keymap...
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f third-stage
sync
" > third-stage

chmod +x third-stage

echo "=> executing third-stage."

LANG=C chroot $rootfs /third-stage

# firstboot will repair all the broken stuff when booting the first time.
echo "#!/bin/sh -e
# Run local parts
run-parts /etc/rc.local.d

exit 0" > etc/rc.local

chmod +x etc/rc.local

mkdir etc/rc.local.d/

echo "#!/bin/sh
# Initialize the system on the first boot
if test -f /firstboot.sh
then
  . /firstboot.sh
  rm /firstboot.sh
fi

exit 0" > etc/rc.local.d/firstboot

chmod +x etc/rc.local.d/firstboot

echo "#!/bin/sh
# fix disk size
fdisk /dev/mmcblk0 << EOF
d
2
n
p
2


w
EOF

# this wont work: have to run it manually with root privileges afterwards.
resize2fs /dev/root

# Generate a hostname
HOSTID=\$(ip addr show dev eth0 | grep ether | awk '{print \$2}' | awk 'BEGIN {FS=\":\"}; {print \$4\$5\$6}')
HOSTNAME=rpi-\$HOSTID
echo \$HOSTNAME > /etc/hostname
echo "127.0.0.1       localhost.localdomain localhost" > /etc/hosts
echo "127.0.1.1       \$HOSTNAME.$DOMAIN \$HOSTNAME" >> /etc/hosts
invoke-rc.d hostname.sh start

# Configure all remaining packages
dpkg --configure -a
dpkg-reconfigure openssh-server

# Set the time
ntpdate europe.pool.ntp.org

# execute resize2fs at next boot (because there is big chance
# fdisk couldn't update the partition table on live systeem. A reboot is required.
mv /resize2fs.sh /etc/rc.local.d/00_resize2fs.sh" > firstboot.sh

chmod +x firstboot.sh

# execute "more.sh" if it exists
if [ -f ./more.sh ]; then
  echo "=> executing more.sh."
	source ./more.sh
fi

echo "#!/bin/bash
apt-get clean
rm -f cleanup
rm etc/ssh/*key
rm etc/ssh/*.pub
rm -rf tmp/*
rm -rf /var/log/*
sync
" > cleanup
chmod +x cleanup
echo "=> executing cleanup."
LANG=C chroot $rootfs /cleanup

cd

umount $bootp
umount $rootp

if [ "$image" != "" ]; then
  kpartx -d $image
  echo "Created Image: $image"
fi

echo "Done... It's `date +%H:%m` and a beautiful day. Enjoy it."