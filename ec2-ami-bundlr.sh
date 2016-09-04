#!/bin/bash
#
#  ec2-ami-bundlr.sh
#  Interactive process to create an Amazon EC2, EBS mounted, HVM/PV machine image
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
#   - This script must be executed by a Vagrant provisioner
#

if [ "$0" != "/tmp/vagrant-shell" ]; then
    echo 'This script must be executed by a Vagrant provisioner'
    exit 1
fi

#
# Commonly used functions.
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

notice 'Starting installation process'

# Check for an existing session.
if [ -e "$AMI_BUNDLR_VARS" ] && [ -d "$AMI_BUNDLR_ROOT" ]; then

    # Backup the project directory.
    outfile="ec2-ami-bundlr.$(date +%s)"

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
notice 'Installing build dependencies..'

yum install -y bind-utils e2fsprogs java-1.8.0-openjdk net-tools ntp perl ruby unzip

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
notice "Writing x.509 certificates to $AMI_BUNDLR_ROOT/keys"

mkdir $AWS_KEYS_DIR

# Write X509 keys from STDIN
if [ $# -ne 0 ]; then
    echo -e "$1" > $AWS_KEYS_DIR/cert.pem
    echo -e "$2" > $AWS_KEYS_DIR/pk.pem
fi

#
# Create OS dependencies.
#
notice 'Creating the filesystem.'

IMAGE_MOUNT_DIR=/mnt/image

if [ ! -d $IMAGE_MOUNT_DIR ]; then
    mkdir $IMAGE_MOUNT_DIR
fi

OS_RELEASE=`cat /etc/*-release | head -1 | awk '{print tolower($0)}' | sed 's/\s(final)$//' | tr ' ' -`
DISK_IMAGE=$AMI_BUNDLR_ROOT/$OS_RELEASE.img
DISK_SIZE=$3

# Create disk mounted as loopback.
dd if=/dev/zero of=$DISK_IMAGE bs=1G count=$DISK_SIZE

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

GRUB_KERNEL=`find $IMAGE_MOUNT_DIR/boot -type f -name 'vmlinuz*.x86_64'       | awk -F / '{print $NF}'`
GRUB_INITRD=`find $IMAGE_MOUNT_DIR/boot -type f -name 'initramfs*.x86_64.img' | awk -F / '{print $NF}'`

perl -p -i -e "s/vmlinuz/$GRUB_KERNEL/g"   $IMAGE_MOUNT_DIR/boot/grub/grub.conf
perl -p -i -e "s/initramfs/$GRUB_INITRD/g" $IMAGE_MOUNT_DIR/boot/grub/grub.conf

#
# Create the AMI image.
#
notice 'Creating the AMI image... This may take a while.'

sleep 60

# Bundle and upload the AMI to S3
BUNDLE_OUTPUT_DIR=$AMI_BUNDLR_ROOT/bundle

mkdir $BUNDLE_OUTPUT_DIR

ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_S3_BUCKET --user $AWS_ACCOUNT_NUMBER --image $DISK_IMAGE --destination $BUNDLE_OUTPUT_DIR --arch x86_64

AMI_MANIFEST=$AWS_S3_BUCKET.manifest.xml

if [ ! -f "$BUNDLE_OUTPUT_DIR/$AMI_MANIFEST" ]; then
    notice 'The image bundling process failed. Please try again.'

    exit 1
else

    # Perform device cleanup
    umount -t /dev/loop0 $IMAGE_MOUNT_DIR/sys
    umount -t /dev/loop0 $IMAGE_MOUNT_DIR/proc
    umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev/shm
    umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev/pts
    umount -t /dev/loop0 $IMAGE_MOUNT_DIR/dev
    umount $IMAGE_MOUNT_DIR
fi

ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_S3_BUCKET --manifest $BUNDLE_OUTPUT_DIR/$AMI_MANIFEST --region=$EC2_REGION

IMAGE_ID=`ec2-register $AWS_S3_BUCKET/$AMI_MANIFEST --name $OS_RELEASE\-$(date +%s) --architecture x86_64 --kernel $AKI_KERNEL | awk '/IMAGE/{print $2}'`

#
# Create EBS-based image from new instance-store.
#
notice 'Creating the EBS-based image... This may take a while.'

if [ "$EC2_REGION" = 'us-east-1' ]; then
    EC2_REGION='us-east-1a'
fi

# Create security group and update ACL permissions.
ec2-create-group ec2-ami-bundlr --description 'EC2 AMI Bundlr group'

IP_ADDRESS=`dig +short myip.opendns.com @resolver1.opendns.com.`

ec2-authorize ec2-ami-bundlr -p 22 -s $IP_ADDRESS/24

# Create temporary SSH keypair to access new instance.
ssh-keygen -b 4096 -t rsa -N '' -f $AMI_BUNDLR_ROOT/keys/ssh.key

chmod 400 $AMI_BUNDLR_ROOT/keys/ssh.key

ec2-import-keypair ec2-ami-bundlr --public-key-file $AMI_BUNDLR_ROOT/keys/ssh.key.pub

# Launch the instance-store.
INSTANCE_ID=`ec2-run-instances $IMAGE_ID --availability-zone $EC2_REGION --group ec2-ami-bundlr --key ec2-ami-bundlr | awk '/INSTANCE/{print $2}'`

sleep 180

AMI_HOSTNAME=`ec2-describe-instances $INSTANCE_ID | awk '/INSTANCE/{print $4}'`

# Create an empty volume and mount to instance.
VOLUME_ID=`ec2-create-volume --size $DISK_SIZE --availability-zone $EC2_REGION | awk '/VOLUME/{print $2}'`

sleep 60

ec2-attach-volume $VOLUME_ID --instance $INSTANCE_ID --device /dev/sdb

# Remotely access the instance; rsync filesystem to mounted volume.
sudo -u root -s ssh -T -o userknownhostsfile=/dev/null -o stricthostkeychecking=no -i $AMI_BUNDLR_ROOT/keys/ssh.key root@$AMI_HOSTNAME << EOF
yum install -y rsync

mkfs.ext4 /dev/xvdf

tune2fs -L '/' /dev/xvdf -i 0

mkdir /mnt/ebs
mount /dev/xvdf /mnt/ebs

rsync -axH /    /mnt/ebs
#rsync -axH /dev /mnt/ebs

touch /mnt/ebs/.autorelabel

umount /mnt/ebs
EOF

# Create the snapshot of the mounted volume.
ec2-create-snapshot $VOLUME_ID --description 'EC2 AMI Bundlr - EBS-based AMI'

sleep 60

# Terminate the instance.
ec2-terminate-instances $INSTANCE_ID

sleep 90

# Perform cleanup.
ec2-delete-group   ec2-ami-bundlr
ec2-delete-keypair ec2-ami-bundlr
ec2-delete-volume  $VOLUME_ID
ec2-deregister     $IMAGE_ID
