#!/bin/bash
#
#  EC2 AMI Bundlr
#  Interactive process to create an Amazon EC2 machine image from a
#  standard CentOS installation.
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
# Set-up the build directory and import configuration variables.
#
source ~/.aws

mkdir $AMI_BUNDLR_ROOT
mkdir $AWS_TOOLS_DIR
mkdir $AWS_KEYS_DIR

#
# Install build dependencies.
#
yum install -y bind-utils e2fsprogs java-1.8.0-openjdk ntp ruby unzip

# Install EC2 AMI/API tools.
curl --silent -o /tmp/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
curl --silent -o /tmp/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

unzip /tmp/ec2-api-tools.zip -d /tmp
unzip /tmp/ec2-ami-tools.zip -d /tmp

cp -r  /tmp/ec2-api-tools-*/* $AWS_TOOLS_DIR
cp -rf /tmp/ec2-ami-tools-*/* $AWS_TOOLS_DIR

rm -rf /tmp/ec2-*

#
# Write x.509 certificates from STDIN to key directory.
#
echo -e "$1" > $AWS_KEYS_DIR/cert.pem
echo -e "$2" > $AWS_KEYS_DIR/pk.pem

#
# Install operating system files on a mounted volume.
#
IMAGE_MOUNT_DIR=/mnt/image

mkdir $IMAGE_MOUNT_DIR

OS_RELEASE=`cat /etc/*-release | head -1 | awk '{print tolower($0)}' | sed 's/\s(final)$//' | tr ' ' -`
DISK_IMAGE=$AMI_BUNDLR_ROOT/$OS_RELEASE.img

# Get value from STDIN
DISK_SIZE=$3

# Create disk volume; mount as loopback.
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

# Install RPM-based Linux distribution.
yum --installroot=$IMAGE_MOUNT_DIR --releasever 6 -y install @core expect

# Install 3rd-party AMI support scripts.
script_path=https://raw.githubusercontent.com/nuxy/linux-sh-archive/master/ec2

curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-get-pubkey   $script_path/get-pubkey.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-password $script_path/set-password.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-set-hostname $script_path/set-hostname.sh
curl --silent -o $IMAGE_MOUNT_DIR/etc/init.d/ec2-post-install $script_path/post-install.sh

chmod 755 $IMAGE_MOUNT_DIR/etc/init.d/ec2-*

/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-get-pubkey   on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-password on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-set-hostname on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig ec2-post-install on
/usr/sbin/chroot $IMAGE_MOUNT_DIR sbin/chkconfig kdump off

touch $IMAGE_MOUNT_DIR/.autorelabel

# Install and configure server dependencies.
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

# Install and configure the kernel files.
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

grub_kernel=`find $IMAGE_MOUNT_DIR/boot -type f -name 'vmlinuz*.x86_64'       | awk -F / '{print $NF}'`
grub_initrd=`find $IMAGE_MOUNT_DIR/boot -type f -name 'initramfs*.x86_64.img' | awk -F / '{print $NF}'`

sed -i "s/vmlinuz/$grub_kernel/g"   $IMAGE_MOUNT_DIR/boot/grub/grub.conf
sed -i "s/initramfs/$grub_initrd/g" $IMAGE_MOUNT_DIR/boot/grub/grub.conf

sync

#
# Bundle the machine image, Upload the bundle, and Register the AMI
#
ntpdate pool.ntp.org

RELEASE_DATE=`date +%s`
RELEASE_NAME=ec2-ami-bundlr\-$RELEASE_DATE

OUTPUT_DIR=$AMI_BUNDLR_ROOT/bundle
mkdir $OUTPUT_DIR

ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_S3_BUCKET --user $AWS_ACCOUNT_NUMBER --image $DISK_IMAGE --destination $OUTPUT_DIR --arch x86_64

AMI_MANIFEST=$AWS_S3_BUCKET.manifest.xml

if [ ! -f $OUTPUT_DIR/$AMI_MANIFEST ]; then
    echo 'The image bundling process failed. Exiting...'
    exit 1
fi

ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_S3_BUCKET --manifest $OUTPUT_DIR/$AMI_MANIFEST --region=$EC2_REGION --retry 3

IMAGE_ID=`ec2-register $AWS_S3_BUCKET/$AMI_MANIFEST --name $OS_RELEASE\-$RELEASE_DATE --architecture x86_64 --kernel $AKI_KERNEL | awk '/IMAGE/{print $2}'`

#
# Create EBS-based image from running instance-store.
#
ip_address=`dig +short myip.opendns.com @resolver1.opendns.com.`

# Create security group and restrict SSH access by IP
ec2-create-group $RELEASE_NAME --description "EC2 AMI Bundlr ($OS_RELEASE)"

ec2-authorize $RELEASE_NAME -p 22 -s $ip_address/24

# Create SSH keypair for accessing the instance.
ssh-keygen -b 4096 -t rsa -N '' -f $AMI_BUNDLR_ROOT/keys/ssh.key

chmod 400 $AMI_BUNDLR_ROOT/keys/ssh.key

ec2-import-keypair $RELEASE_NAME --public-key-file $AMI_BUNDLR_ROOT/keys/ssh.key.pub

# Launch the instance-store.
avail_zone=$EC2_REGION

if [ $avail_zone = 'us-east-1' ]; then
    avail_zone='us-east-1a'
fi

INSTANCE_ID=`ec2-run-instances $IMAGE_ID --availability-zone $avail_zone --group $RELEASE_NAME --key $RELEASE_NAME | awk '/INSTANCE/{print $2}'`

while true; do
    api_response=`ec2-describe-instances $INSTANCE_ID | awk '/INSTANCE/{print $6}'`

    if [ "$api_response" = '0' ]; then
        echo 'The instance failed to initialize and was terminated. Exiting...'
        exit 1
    fi

    if [ "$api_response" = 'running' ]; then
        break
    fi

    sleep 5
done

# Create an empty volume and mount to instance.
VOLUME_ID=`ec2-create-volume --size $DISK_SIZE --availability-zone $avail_zone | awk '/VOLUME/{print $2}'`

while true; do
    api_response=`ec2-describe-volumes $VOLUME_ID | awk '/VOLUME/{print $5}'`

    if [ "$api_response" = 'available' ]; then
        break
    fi

    sleep 5
done

ec2-attach-volume $VOLUME_ID --instance $INSTANCE_ID --device /dev/sdb

while true; do
    api_response=`ec2-describe-volumes $VOLUME_ID | awk '/ATTACHMENT/{print $5}'`

    if [ "$api_response" = 'attached' ]; then
        break
    fi

    sleep 5
done

# Remotely access the instance using SSH when available.
ec2_hostname=`ec2-describe-instances $INSTANCE_ID | awk '/INSTANCE/{print $4}'`

while true; do
    ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $AMI_BUNDLR_ROOT/keys/ssh.key root@$ec2_hostname << EOF
service iptables stop

yum install -y rsync

mkfs.ext4 /dev/xvdf
tune2fs -L '/' /dev/xvdf -i 0

mkdir /mnt/ebs
mount /dev/xvdf /mnt/ebs

rsync -axH / /mnt/ebs
touch /mnt/ebs/.autorelabel

umount /mnt/ebs
EOF

    if [ $? -eq 0 ]; then
        break
    fi

    sleep 5
done

# Create the snapshot of the mounted volume.
SNAPSHOT_ID=`ec2-create-snapshot $VOLUME_ID --description "EC2 AMI Bundlr ($OS_RELEASE)" | awk '/SNAPSHOT/{print $2}'`

while true; do
    api_response=`ec2-describe-snapshots $SNAPSHOT_ID | awk '/SNAPSHOT/{print $4}'`

    if [ "$api_response" = 'completed' ]; then
        break
    fi

    sleep 5
done

# Terminate the instance.
ec2-terminate-instances $INSTANCE_ID

while true; do
    api_response=`ec2-describe-instances $INSTANCE_ID | awk '/INSTANCE/{print $4}'`

    if [ "$api_response" = 'terminated' ]; then
        break
    fi

    sleep 5
done

# Perform cleanup.
ec2-delete-group   $RELEASE_NAME
ec2-delete-keypair $RELEASE_NAME
ec2-delete-volume  $VOLUME_ID
ec2-deregister     $IMAGE_ID
