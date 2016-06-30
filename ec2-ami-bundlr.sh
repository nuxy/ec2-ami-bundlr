#!/bin/sh
#
#  ec2-ami-bundlr.sh
#  Interactive process to create an Amazon EC2 HVM/PV machine image
#  from a standard Linux installation.
#
#  Copyright 2016, Marc S. Brooks (http://mbrooks.info)
#  Licensed under the MIT license:
#  http://www.opensource.org/licenses/mit-license.php
#
#  Supported systems:
#    RHEL
#    CentOS
#    Fedora
#
#  Dependencies:
#    OpenSSL
#
#  Notes:
#   - This script has been tested to work with Linux
#   - This script must be executed as root
#

AMI_BUNDLR_VARS="~/.aws"

source $AMI_BUNDLR_VARS

#
# Check for an existing session.
#
if [ -e "$AMI_BUNDLR_VARS" ] && [ -d "$AMI_BUNDLR_ROOT" ]; then

    # Backup session and remove stored data.
    timestamp=`date +%s`
    tar cfz ec2-ami-bundlr.$timestamp.tar.gz -C $AMI_BUNDLR_VARS $AMI_BUNDLR_ROOT
    rm -rf $AMI_BUNDLR_VARS $AMI_BUNDLR_ROOT
fi

mkdir $AMI_BUNDLR_ROOT

#
# Install build dependencies.
#
notice "Installing build dependencies.."

yum install -y e2fsprogs java-1.8.0-openjdk net-tools ntp perl ruby unzip

# Synchronize server time.
ntpdate pool.ntp.org

# Install the AWS AMI/API tools.
AWS_TOOLS_DIR=$AMI_BUNDLR_ROOT/tools

mkdir $AWS_TOOLS_DIR

curl -o /tmp/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
curl -o /tmp/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

unzip /tmp/ec2-api-tools.zip -d /tmp
unzip /tmp/ec2-ami-tools.zip -d /tmp

cp -r  /tmp/ec2-api-tools-*/* $AWS_TOOLS_DIR
cp -rf /tmp/ec2-ami-tools-*/* $AWS_TOOLS_DIR

rm -rf /tmp/ec2-*

#
# Set-up signing certificates.
#
notice "Writing SSL certificates to $AMI_BUNDLR_ROOT/keys"

AWS_KEYS_DIR=$AMI_BUNDLR_ROOT/keys

mkdir $AWS_KEYS_DIR

echo -e "$EC2_CERT"        > $AWS_KEYS_DIR/cert.pem
echo -e "$EC2_PRIVATE_KEY" > $AWS_KEYS_DIR/pk.pem

#
# Create OS dependencies.
#
notice "Creating the filesystem."

IMAGE_MOUNT_DIR=/mnt/image

mkdir $IMAGE_MOUNT_DIR

OS_RELEASE=`cat /etc/*-release | head -1 | awk '{print tolower($0)}' | tr ' ' -`
DISK_IMAGE=$AMI_BUNDLR_ROOT/$OS_RELEASE.img

# Create disk mounted as loopback.
dd if=/dev/zero of=$DISK_IMAGE bs=1M count=2048

mkfs.ext4 -F -j $DISK_IMAGE

mount -o loop $DISK_IMAGE $IMAGE_MOUNT_DIR

# Create the filesystem.
mkdir -p $IMAGE_MOUNT_DIR/{dev,etc,proc,sys}
mkdir -p $IMAGE_MOUNT_DIR/var/{cache,lock,log,lib/rpm}

# Create required devices.
mknod $IMAGE_MOUNT_DIR/dev/console c 5 1
mknod $IMAGE_MOUNT_DIR/dev/null    c 1 3
mknod $IMAGE_MOUNT_DIR/dev/urandom c 1 9
mknod $IMAGE_MOUNT_DIR/dev/zero    c 1 5

chmod 0644 $IMAGE_MOUNT_DIR/dev/console
chmod 0644 $IMAGE_MOUNT_DIR/dev/null
chmod 0644 $IMAGE_MOUNT_DIR/dev/urandom
chmod 0644 $IMAGE_MOUNT_DIR/dev/zero

mount -o bind /dev     $IMAGE_MOUNT_DIR/dev
mount -o bind /dev/pts $IMAGE_MOUNT_DIR/dev/pts
mount -o bind /dev/shm $IMAGE_MOUNT_DIR/dev/shm
mount -o bind /proc    $IMAGE_MOUNT_DIR/proc
mount -o bind /sys     $IMAGE_MOUNT_DIR/sys

# Install the operating system and kernel.
yum --installroot=/mnt/image --releasever 6 -y install @core
yum --installroot=/mnt/image --releasever 6 -y install kernel

# Install the Grub bootloader
cat << EOF > /mnt/image/boot/grub/grub.conf
default 0
timeout 0

title Linux ($OS_RELEASE)
root (hd0)
kernel /boot/vmlinuz ro root=/dev/xvde1 console=hvc0 quiet
initrd /boot/initramfs
EOF

ln -s /boot/grub/grub.conf /mnt/image/boot/grub/menu.lst

kernel=`find /mnt/image/boot -type f -name "vmlinuz*.x86_64" | awk -F / '{print $NF}'`
initramfs=`find /mnt/image/boot -type f -name "initramfs*.x86_64.img" | awk -F / '{print $NF}'`

perl -p -i -e "s/vmlinuz/$kernel/g" /mnt/image/boot/grub/grub.conf
perl -p -i -e "s/initramfs/$initramfs/g" /mnt/image/boot/grub/grub.conf

# Install 3rd-party AMI support scripts.
SCRIPT_PATH=https://raw.githubusercontent.com/nuxy/linux-sh-archive/master/ec2

curl -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-get-pubkey   $SCRIPT_PATH/get-pubkey.sh
curl -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-password $SCRIPT_PATH/set-password.sh
curl -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-hostname $SCRIPT_PATH/set-hostname.sh
curl -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-post-install $SCRIPT_PATH/post-install.sh

/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-get-pubkey   on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-password on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-hostname on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-post-install on

touch $IMAGE_MOUNT_DIR/.autorelabel

# Configure the image services.
cat << EOF > $IMAGE_MOUNT_DIR/etc/fstab
/dev/xvde1  /           ext4         defaults          1    1
none        /dev/pts    devpts       gid=5,mode=620    0    0
none        /dev/shm    tmpfs        defaults          0    0
none        /proc       proc         defaults          0    0
none        /sys        sysfs        defaults          0    0
EOF

cat << EOF > $IMAGE_MOUNT_DIR/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

cat << EOF > $IMAGE_MOUNT_DIR/etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=dhcp
DEVICE=eth0
NM_CONTROLLED=yes
ONBOOT=yes
EOF

perl -p -i -e "s/PermitRootLogin no/PermitRootLogin without-password/g" /etc/ssh/sshd_config

/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig network on

umount $IMAGE_MOUNT_DIR

#
# Create the AMI image.
#
notice "Creating the AMI image... This may take a while."

# Bundle and upload the AMI to S3
BUNDLE_OUTPUT_DIR=$AMI_BUNDLR_ROOT/bundle

mkdir $BUNDLE_OUTPUT_DIR

ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_S3_BUCKET --user $AWS_ACCOUNT_NUMBER --image $DISK_IMAGE --destination $BUNDLE_OUTPUT_DIR --arch x86_64

ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_S3_BUCKET --manifest $BUNDLE_OUTPUT_DIR/$AWS_S3_BUCKET.manifest.xml --region=$EC2_REGION

ec2-register $AWS_S3_BUCKET/$AWS_S3_BUCKET.manifest.xml --name $OS_RELEASE --architecture x86_64 --kernel $AKI_KERNEL
