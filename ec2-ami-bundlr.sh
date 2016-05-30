#!/bin/bash
#
#  ec2-ami-bundlr.sh
#  Interactive script to create an HVM/PV machine image
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
#    openssl
#
#  Notes:
#   - This script has been tested to work with Linux
#   - This script must be executed as root
#

if [ "$EUID" -ne 0 ]; then
  echo "This script MUST be executed as root. Exiting.."
  exit
fi

BUILD_CONF=~/.aws
BUILD_ROOT=~/ec2-ami-bundlr

# Begin program.
clear && cat << EOF

Welcome to the AMI builder interactive setup. It is assumed that you:

  1. Installed Linux by ISO and have a standard configured system.
  2. Are running the operating system on a single partition.
  3. Have free disk space available equal to (or greater) filesystem in use.
  4. Are NOT already running your system in a VM (the Cloud) environment.
  5. Have an Amazon Web Services account with EC2/S3 root or IAM access.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

Copyright 2016, Marc S. Brooks (https://mbrooks.info)

EOF

error() {
    echo -en "\n\033[0;31m$1\033[0m"
    sleep 1
    clear
}

notice() {
    echo -e "\033[1m$1\033[0m\n"
    sleep 1
}

while true; do
    read -p "Ready to get started? [Y/n] " line

    case $line in
        [yY])
            sleep 1
            clear
            break
            ;;
        [nN])
            echo -e "Aborted..\n"
            exit 0
            ;;
         *)
    esac
done

# Prompt EC2_CERT value.
while true; do
    echo -e "Enter the contents of your X.509 EC2 certificate below: "

    # Get certificate from STDIN
    while read -r line; do
        if [ "$line" != "" ]; then
            EC2_CERT+="$line\n"
        fi

        if [ "$line" == "-----END CERTIFICATE-----" ]; then
            break
        fi
    done

    # Validate the certificate.
    output=$(echo | openssl rsa -in `echo "$EC2_CERT" & cat` -check 2>&1)

    if [[ $output =~ 'Error' ]]; then
        error "The certificate entered is not valid."
        continue
    fi

    clear
    break
done

# Get EC2_PRIVATE_KEY value.
while true; do
    echo -e "Enter the contents your X.509 EC2 private key below: "

    # Get certificate from STDIN
    while read -r line; do
        if [ "$line" != "" ]; then
            EC2_PRIVATE_KEY+="$line\n"
        fi

        if [ "$line" == "-----END RSA PRIVATE KEY-----" ]; then
            break
        fi
    done

    # Validate the certificate.
    output=$(echo | openssl x509 -in `echo "$EC2_PRIVATE_KEY" & cat` -text -noout -check 2>&1)

    if [[ $output =~ 'Error' ]]; then
        error "The private key entered is not valid."
        continue
    fi

    clear
    break
done

# Prompt AWS_ACCOUNT_NUMBER value.
while true; do
    read -p "Enter your AWS account number: " line

    if ! [[ $line =~ ^[0-9\-]{8,15}$ ]]; then
        error "The account number entered is not valid."
        continue
    else
        AWS_ACCOUNT_NUMBER=`echo $line | tr -d '-'`

        clear
        break
    fi
done

# Prompt AWS_ACCESS_KEY value.
while true; do
    read -p "Enter your AWS access key: " line

    if ! [[ $line =~ ^[A-Z0-9]{20}$ ]]; then
        error "The access key entered is not valid."
        continue
    else
        AWS_ACCESS_KEY=$line

        clear
        break
    fi
done

# Prompt AWS_SECRET_KEY value.
while true; do
    read -p "Enter your AWS secret key: " line

    if ! [[ $line =~ ^[a-zA-Z0-9\+\/]{39,40}$ ]]; then
        error "The secret key entered is not valid."
        continue
    else
        AWS_SECRET_KEY=$line

        clear
        break
    fi
done

# Prompt AWS_S3_BUCKET value.
while true; do
    read -p "Enter your AWS S3 bucket: " line

    if ! [[ $line =~ ^[^\.\-]?[a-zA-Z0-9\.\-]{1,63}[^\.\-]?$ ]]; then
        error "The bucket name entered is not valid."
        continue
    else
        AWS_S3_BUCKET=$line

        clear
        break
    fi
done

# Prompt EC2_REGION value.
while true; do

    cat << EOF
Choose your EC2 region from the list below:

 1. US East (N. Virginia)      us-east-1
 2. US West (N. California)    us-west-1
 3. US West (Oregon)           us-west-2
 4. EU (Ireland)               eu-west-1
 5. EU (Frankfurt)             eu-central-1
 6. Asia Pacific (Tokyo)       ap-northeast-1
 7. Asia Pacific (Seoul)       ap-northeast-2
 8. Asia Pacific (Singapore)   ap-southeast-1
 9. Asia Pacific (Sydney)      ap-southeast-2
10. South America (São Paulo)  sa-east-1

EOF

    read -p "Region [1-10] " line

    case $line in
        1)
            EC2_REGION="us-east-1"
            ;;
        2)
            EC2_REGION="us-west-1"
            ;;
        3)
            EC2_REGION="us-west-2"
            ;;
        4)
            EC2_REGION="eu-west-1"
            ;;
        5)
            EC2_REGION="eu-central-1"
            ;;
        6)
            EC2_REGION="ap-northeast-1"
            ;;
        7)
            EC2_REGION="ap-northeast-2"
            ;;
        8)
            EC2_REGION="ap-southeast-1"
            ;;
        9)
            EC2_REGION="ap-southeast-2"
            ;;
        10)
            EC2_REGION="sa-east-1"
            ;;
         *)
            error "Not a valid entry."
            continue
    esac

    if [ "$EC2_REGION" != "" ]; then
        sleep 1
        clear
        break
    fi
done

#
# Check for an existing sessions.
#
if [ -e "$BUILD_CONF" ]; then

    # Backup session and remove stored data.
    timestamp=`date +%s`
    tar cfz ec2-ami-bundlr.$timestamp.tar.gz $BUILD_CONF $BUILD_ROOT
    rm -rf $BUILD_CONF $BUILD_ROOT
fi

mkdir $BUILD_ROOT

#
# Install build dependencies.
#
notice "Installing build dependencies.."

yum install -y e2fsprogs java-1.8.0-openjdk net-tools ntp perl ruby unzip

# Synchronize server time.
ntpdate pool.ntp.org

# Install the AWS AMI/API tools.
BUILD_TOOLS_DIR=$BUILD_ROOT/tools

mkdir $BUILD_TOOLS_DIR

curl -o /tmp/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
curl -o /tmp/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

unzip /tmp/ec2-api-tools.zip -d /tmp
unzip /tmp/ec2-ami-tools.zip -d /tmp

cp -r  /tmp/ec2-api-tools-*/* $BUILD_TOOLS_DIR
cp -rf /tmp/ec2-ami-tools-*/* $BUILD_TOOLS_DIR

rm -rf /tmp/ec2-*

#
# Set-up signing certificates.
#
notice "Writing SSL certificates to $BUILD_ROOT/keys"

BUILD_KEYS_DIR=$BUILD_ROOT/keys

mkdir $BUILD_KEYS_DIR

echo -e "$EC2_CERT"        > $BUILD_KEYS_DIR/cert.pem
echo -e "$EC2_PRIVATE_KEY" > $BUILD_KEYS_DIR/pk.pem

#
# Set-up build environment.
#
notice "Writing the configuration to $BUILD_CONF"

cat << EOF > $BUILD_CONF

# Amazon EC2 account.
export AWS_ACCOUNT_NUMBER=$AWS_ACCOUNT_NUMBER
export AWS_ACCESS_KEY=$AWS_ACCESS_KEY
export AWS_SECRET_KEY=$AWS_SECRET_KEY
export AWS_S3_BUCKET=$AWS_S3_BUCKET

# Amazon EC2 Tools.
export EC2_HOME=$BUILD_TOOLS_DIR
export EC2_PRIVATE_KEY=$BUILD_KEYS_DIR/pk.pem
export EC2_CERT=$BUILD_KEYS_DIR/cert.pem
export EC2_REGION=$EC2_REGION

export JAVA_HOME=/usr
export PATH=$PATH:$EC2_HOME/bin:$BUILD_TOOLS/bin
EOF

chmod 600 $BUILD_CONF

# Import shell variables.
source $BUILD_CONF

#
# Create the AMI image.
#
notice "Creating the AMI image... This may take a while."

BUILD_MOUNT_DIR=/mnt/image

mkdir $BUILD_MOUNT_DIR

OS_RELEASE=`. /etc/os-release; echo $NAME-$VERSION_ID | awk '{print tolower($0)}' | tr ' ' -`
DISK_IMAGE=$BUILD_ROOT/$OS_RELEASE.img
PARTITION=`df | grep '/$' | awk -F '[[:space:]]' '{print $1}'`

# Create disk mounted as loopback.
dd if=$PARTITION of=$DISK_IMAGE bs=1M count=2024

mkfs.ext4 -F -j $DISK_IMAGE

mount -o loop $DISK_IMAGE $BUILD_MOUNT_DIR

# Copy the root partition (exclude AMI non-required files).
BUILD_EXCLUDES="--exclude=$BUILD_ROOT --exclude=$(readlink -f $0) "

for file in dev media mnt proc sys; do
    BUILD_EXCLUDES+="--exclude=$file "
done

tar cf - $BUILD_EXCLUDES / | (cd $BUILD_MOUNT_DIR && tar xvf -)

mkdir -p $BUILD_MOUNT_DIR/{dev,proc,sys}

# Create required devices.
mknod $BUILD_MOUNT_DIR/dev/console c 5 1
mknod $BUILD_MOUNT_DIR/dev/null    c 1 3
mknod $BUILD_MOUNT_DIR/dev/urandom c 1 9
mknod $BUILD_MOUNT_DIR/dev/zero    c 1 5

chmod 0644 $BUILD_MOUNT_DIR/dev/console
chmod 0644 $BUILD_MOUNT_DIR/dev/null
chmod 0644 $BUILD_MOUNT_DIR/dev/urandom
chmod 0644 $BUILD_MOUNT_DIR/dev/zero

# Install 3rd-party AMI support scripts.
SCRIPT_PATH=https://raw.githubusercontent.com/nuxy/linux-sh-archive/master/ec2

curl -o $BUILD_MOUNT_DIR/etc/init.d/ec2-get-pubkey   $SCRIPT_PATH/get-pubkey.sh
curl -o $BUILD_MOUNT_DIR/etc/init.d/ec2-set-password $SCRIPT_PATH/set-password.sh
curl -o $BUILD_MOUNT_DIR/etc/init.d/ec2-set-hostname $SCRIPT_PATH/set-hostname.sh
curl -o $BUILD_MOUNT_DIR/etc/init.d/ec2-post-install $SCRIPT_PATH/post-install.sh

/usr/sbin/chroot $BUILD_MOUNT_DIR sbin/chkconfig ec2-get-pubkey   on
/usr/sbin/chroot $BUILD_MOUNT_DIR sbin/chkconfig ec2-set-password on
/usr/sbin/chroot $BUILD_MOUNT_DIR sbin/chkconfig ec2-set-hostname on
/usr/sbin/chroot $BUILD_MOUNT_DIR sbin/chkconfig ec2-post-install on

# Configure the image services.
cat << EOF > $BUILD_MOUNT_DIR/etc/fstab
/dev/xvde1 / ext4 defaults,noatime,nodiratime 1 1
EOF

cat << EOF > $BUILD_MOUNT_DIR/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

cat << EOF > $BUILD_MOUNT_DIR/etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=dhcp
DEVICE=eth0
NM_CONTROLLED=yes
ONBOOT=yes
EOF

perl -p -i -e "s/PermitRootLogin no/PermitRootLogin without-password/g" /etc/ssh/sshd_config

/usr/sbin/chroot $BUILD_MOUNT_DIR sbin/chkconfig network on

# Bundle and upload the AMI to S3
BUILD_OUTPUT_DIR=$BUILD_ROOT/bundle

mkdir $BUILD_OUTPUT_DIR

ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_S3_BUCKET --user $AWS_ACCOUNT_NUMBER --region=$EC2_REGION --image $DISK_IMAGE --destination $BUILD_OUTPUT_DIR --arch `arch`

ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_S3_BUCKET --manifest $BUILD_OUTPUT_DIR/$AWS_S3_BUCKET.manifest.xml
