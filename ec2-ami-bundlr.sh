#!/bin/bash
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
#    CentOS
#
#  Dependencies:
#    OpenSSL
#
#  Notes:
#   - This script has been tested to work with Linux
#   - This script must be executed as root
#

notice () {
    echo -e "\033[1m$1\033[0m\n"
    sleep 1
}

#
# Start the installation.
#
AMI_BUNDLR_VARS=~/.aws

source $AMI_BUNDLR_VARS

notice "Starting installation process"

# Check for an existing session.
if [ -e "$AMI_BUNDLR_VARS" ] && [ -d "$AMI_BUNDLR_ROOT" ]; then
    timestamp=`date +%s`

    # Backup the project directory.
    outfile="ec2-ami-bundlr.$timestamp.tar.gz"

    notice "Build exists. Backing up files to $outfile"

    tar cfz $outfile --add-file $AMI_BUNDLR_VARS --directory $AMI_BUNDLR_ROOT --absolute-names

    # Remove directory.
    rm -rf $AMI_BUNDLR_ROOT
fi

# Create new project directory.
mkdir $AMI_BUNDLR_ROOT

#
# Install build dependencies.
#
notice "Installing build dependencies.."

yum install -y e2fsprogs java-1.8.0-openjdk net-tools ntp perl ruby unzip

# Synchronize server time.
ntpdate pool.ntp.org

# Install the AWS AMI/API tools.
mkdir $AWS_TOOLS_DIR

curl --silent -o /tmp/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
curl --silent -o /tmp/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

unzip /tmp/ec2-api-tools.zip -d /tmp
unzip /tmp/ec2-ami-tools.zip -d /tmp

cp -r  /tmp/ec2-api-tools-*/* $AWS_TOOLS_DIR
cp -rf /tmp/ec2-ami-tools-*/* $AWS_TOOLS_DIR

rm -rf /tmp/ec2-*

#
# Set-up signing certificates.
#
notice "Writing SSL certificates to $AMI_BUNDLR_ROOT/keys"

mkdir $AWS_KEYS_DIR

# Write X509 keys from STDIN
if [ $# -ne 0 ]; then
    echo -e "$1" > $AWS_KEYS_DIR/cert.pem
    echo -e "$2" > $AWS_KEYS_DIR/pk.pem
fi

#
# Create OS dependencies.
#
notice "Creating the filesystem."

IMAGE_MOUNT_DIR=/mnt/image

if [ ! -d $IMAGE_MOUNT_DIR ]; then
    mkdir $IMAGE_MOUNT_DIR
fi

OS_RELEASE=`cat /etc/*-release | head -1 | awk '{print tolower($0)}' | tr ' ' -`
DISK_IMAGE=$AMI_BUNDLR_ROOT/$OS_RELEASE.img

# Create disk mounted as loopback.
dd if=/dev/zero of=$DISK_IMAGE bs=1M count=$3

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

# Install the operating system.
yum --installroot=$IMAGE_MOUNT_DIR --releasever 6 -y install @core expect

# Install 3rd-party AMI support scripts.
SCRIPT_PATH=https://raw.githubusercontent.com/nuxy/linux-sh-archive/master/ec2

curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-get-pubkey   $SCRIPT_PATH/get-pubkey.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-password $SCRIPT_PATH/set-password.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-hostname $SCRIPT_PATH/set-hostname.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-post-install $SCRIPT_PATH/post-install.sh

chmod 755 $IMAGE_MOUNT_DIR/etc/init.d/ec2-*

/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-get-pubkey   on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-password on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-hostname on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-post-install on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig kdump off

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

/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig network on

cat << EOF >> $IMAGE_MOUNT_DIR/etc/ssh/sshd_config
RSAAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitRootLogin without-password
EOF

/usr/sbin/chroot $IMAGE_MOUNT_DIR mkdir /root/.ssh

# Install the kernel and dependencies.
yum --installroot=$IMAGE_MOUNT_DIR --releasever 6 -y install kernel

cat << EOF > $IMAGE_MOUNT_DIR/boot/grub/grub.conf
default 0
timeout 0

title Linux ($OS_RELEASE)
root (hd0)
kernel /boot/vmlinuz ro root=/dev/xvde1 console=hvc0 quiet
initrd /boot/initramfs
EOF

ln -s /boot/grub/grub.conf $IMAGE_MOUNT_DIR/boot/grub/menu.lst

GRUB_KERNEL=`find $IMAGE_MOUNT_DIR/boot -type f -name "vmlinuz*.x86_64" | awk -F / '{print $NF}'`
GRUB_INITRD=`find $IMAGE_MOUNT_DIR/boot -type f -name "initramfs*.x86_64.img" | awk -F / '{print $NF}'`

perl -p -i -e "s/vmlinuz/$GRUB_KERNEL/g"   $IMAGE_MOUNT_DIR/boot/grub/grub.conf
perl -p -i -e "s/initramfs/$GRUB_INITRD/g" $IMAGE_MOUNT_DIR/boot/grub/grub.conf

#
# Create the AMI image.
#
notice "Creating the AMI image... This may take a while."

sleep 60

# Bundle and upload the AMI to S3
BUNDLE_OUTPUT_DIR=$AMI_BUNDLR_ROOT/bundle

mkdir $BUNDLE_OUTPUT_DIR

ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_S3_BUCKET --user $AWS_ACCOUNT_NUMBER --image $DISK_IMAGE --destination $BUNDLE_OUTPUT_DIR --arch x86_64

AMI_MANIFEST=$AWS_S3_BUCKET.manifest.xml

if [ -f "$BUNDLE_OUTPUT_DIR/$AMI_MANIFEST" ]; then
    ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_S3_BUCKET --manifest $BUNDLE_OUTPUT_DIR/$AMI_MANIFEST --region=$EC2_REGION

    ec2-register $AWS_S3_BUCKET/$AMI_MANIFEST --name $OS_RELEASE --architecture x86_64 --kernel $AKI_KERNEL --virtualization-type $4
else
    notice "The image bundling process failed. Please try again."
fi

# Perform device cleanup
umount -t /dev/loop0 $IMAGE_MOUNT_DIR/sys
umount -t /dev/loop0 $IMAGE_MOUNT_DIR/proc
umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev/shm
umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev/pts
umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev
umount $IMAGE_MOUNT_DIR
