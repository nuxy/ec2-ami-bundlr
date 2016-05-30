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

BUILD_ROOT=/mnt
BUILD_KEYS=$BUILD_ROOT/keys
BUILD_CONF=~/.aws

# Begin program.
cat << EOF

Welcome to the AMI builder interactive setup. It is assumed that you have:

  1. Installed Linux by ISO and have a standard configured system.
  2. Running the operating system on a single partition.
  3. Free disk space that is equal to, or greater than, filesystem in use.
  4. Are NOT already running in a VM (the Cloud) environment.
  5. Have an Amazon Web Services account with EC2/S3 access.

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
    echo -e "Enter your X.509 EC2 certificate below: "

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
    echo -e "Enter your X.509 EC2 private key below: "

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
    read -p "Enter your AWS account number below: " line

    if ! [[ $line =~ ^[0-9\-]{8,15}$ ]]; then
        error "The account number entered is not valid."
        continue
    else
        AWS_ACCOUNT_NUMBER=`echo $line | tr -d '-'`

        clear
        break
    fi
done

# Prompt AWS_AMI_BUCKET value.
while true; do
    read -p "Enter your AWS AMI bucket: " line

    if ! [[ $line =~ ^[^\.\-]?[a-zA-Z0-9\.\-]{1,63}[^\.\-]?$ ]]; then
        error "The bucket name entered is not valid."
        continue
    else
        AWS_AMI_BUCKET=$line

        clear
        break
    fi
done

# Prompt AWS_ACCESS_KEY value.
while true; do
    read -p "Enter your AWS access key ID: " line

    if ! [[ $line =~ ^[A-Z0-9]{20}$ ]]; then
        error "The access key ID entered is not valid."
        continue
    else
        AWS_ACCESS_KEY=$line

        clear
        break
    fi
done

# Prompt AWS_SECRET_KEY value.
while true; do
    read -p "Enter your AWS secret access key: " line

    if ! [[ $line =~ ^[a-zA-Z0-9\+\/]{39,40}$ ]]; then
        error "The secret access key entered is not valid."
        continue
    else
        AWS_SECRET_KEY=$line

        clear
        break
    fi
done

# Prompt EC2_URL value.
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
            EC2_URL="ec2.us-east-1.amazonaws.com"
            ;;
        2)
            EC2_URL="ec2.us-west-1.amazonaws.com"
            ;;
        3)
            EC2_URL="ec2.us-west-2.amazonaws.com"
            ;;
        4)
            EC2_URL="ec2.eu-west-1.amazonaws.com"
            ;;
        5)
            EC2_URL="ec2.eu-central-1.amazonaws.com"
            ;;
        6)
            EC2_URL="ec2.ap-northeast-1.amazonaws.com"
            ;;
        7)
            EC2_URL="ec2.ap-northeast-2.amazonaws.com"
            ;;
        8)
            EC2_URL="ec2.ap-southeast-1.amazonaws.com"
            ;;
        9)
            EC2_URL="ec2.ap-southeast-2.amazonaws.com"
            ;;
        10)
            EC2_URL="ec2.sa-east-1.amazonaws.com"
            ;;
         *)
            error "Not a valid entry."
            continue
    esac

    if [ "$EC2_URL" != "" ]; then
        sleep 1
        clear
        break
    fi
done

#
# Install build dependencies.
#
notice "Installing build dependencies.."

yum install -y e2fsprogs java-1.8.0-openjdk net-tools perl ruby unzip

# Install the AWS AMI/API tools.
BUILD_TOOLS=$BUILD_ROOT/tools

mkdir $BUILD_TOOLS

curl -o /tmp/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
curl -o /tmp/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

unzip /tmp/ec2-api-tools.zip -d /tmp
unzip /tmp/ec2-ami-tools.zip -d /tmp

cp -r  /tmp/ec2-api-tools-*/* $BUILD_TOOLS
cp -rf /tmp/ec2-ami-tools-*/* $BUILD_TOOLS

rm -rf /tmp/ec2-*

#
# Set-up signing certificates.
#
notice "Writing SSL certificates to $BUILD_ROOT/keys"

if [ ! -e $BUILD_KEYS ]; then
    mkdir $BUILD_KEYS
fi

echo -e "$EC2_CERT"        > $BUILD_KEYS/cert.pem
echo -e "$EC2_PRIVATE_KEY" > $BUILD_KEYS/pk.pem

#
# Set-up build environment.
#
notice "Writing the configuration to $BUILD_CONF"

cat << EOF > $BUILD_CONF

# Amazon EC2 account.
export AWS_ACCOUNT_NUMBER=$AWS_ACCOUNT_NUMBER
export AWS_ACCESS_KEY=$AWS_ACCESS_KEY
export AWS_SECRET_KEY=$AWS_SECRET_KEY
export AWS_AMI_BUCKET=$AWS_AMI_BUCKET

# Amazon EC2 Tools.
export EC2_HOME=$BUILD_ROOT/tools
export EC2_PRIVATE_KEY=$BUILD_KEYS/pk.pem
export EC2_CERT=$BUILD_KEYS/cert.pem
export EC2_URL=$EC2_URL

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

# Create disk mounted as loopback.
OS_RELEASE=`. /etc/os-release; echo $NAME-$VERSION_ID | awk '{print tolower($0)}' | tr ' ' -`
PARTITION=`df | grep '/$' | awk -F '[[:space:]]' '{print $1}'`

BUILD_IMAGE=$BUILD_ROOT/image

dd if=$PARTITION of=$BUILD_ROOT/$OS_RELEASE.img bs=1M count=2024

mkfs.ext4 -F -j $BUILD_ROOT/$OS_RELEASE.img

mkdir -p $BUILD_IMAGE

mount -o loop $BUILD_ROOT/$OS_RELEASE.img $BUILD_IMAGE

# Copy the root partition (exclude AMI non-required files).
BUILD_EXCLUDES="--exclude=$(readlink -f $0) "

for file in dev media mnt proc sys; do
    BUILD_EXCLUDES+="--exclude=$file "
done

tar cf - $BUILD_EXCLUDES / | (cd $BUILD_IMAGE && tar xvf -)

mkdir -p $BUILD_IMAGE/{dev,proc,sys}

# Create required devices.
mknod $BUILD_IMAGE/dev/console c 5 1
mknod $BUILD_IMAGE/dev/null    c 1 3
mknod $BUILD_IMAGE/dev/urandom c 1 9
mknod $BUILD_IMAGE/dev/zero    c 1 5

chmod 0644 $BUILD_IMAGE/dev/console
chmod 0644 $BUILD_IMAGE/dev/null
chmod 0644 $BUILD_IMAGE/dev/urandom
chmod 0644 $BUILD_IMAGE/dev/zero

# Install 3rd-party AMI support scripts.
SCRIPT_PATH=https://raw.githubusercontent.com/nuxy/linux-sh-archive/master/ec2

curl -o $BUILD_IMAGE/etc/init.d/ec2-get-pubkey   $SCRIPT_PATH/get-pubkey.sh
curl -o $BUILD_IMAGE/etc/init.d/ec2-set-password $SCRIPT_PATH/set-password.sh
curl -o $BUILD_IMAGE/etc/init.d/ec2-set-hostname $SCRIPT_PATH/set-hostname.sh
curl -o $BUILD_IMAGE/etc/init.d/ec2-post-install $SCRIPT_PATH/post-install.sh

/usr/sbin/chroot $BUILD_IMAGE sbin/chkconfig ec2-get-pubkey   on
/usr/sbin/chroot $BUILD_IMAGE sbin/chkconfig ec2-set-password on
/usr/sbin/chroot $BUILD_IMAGE sbin/chkconfig ec2-set-hostname on
/usr/sbin/chroot $BUILD_IMAGE sbin/chkconfig ec2-post-install on

# Configure the image services.
cat << EOF > $BUILD_IMAGE/etc/fstab
/dev/xvde1 / ext4 defaults,noatime,nodiratime 1 1
EOF

cat << EOF > $BUILD_IMAGE/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

cat << EOF > $BUILD_IMAGE/etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=dhcp
DEVICE=eth0
NM_CONTROLLED=yes
ONBOOT=yes
EOF

perl -p -i -e "s/PermitRootLogin no/PermitRootLogin without-password/g" /etc/ssh/sshd_config

/usr/sbin/chroot $BUILD_IMAGE sbin/chkconfig network on

# Bundle and upload the image to S3
ec2-bundle-image --cert $EC2_CERT --privatekey $EC2_PRIVATE_KEY --prefix $AWS_AMI_BUCKET --user $AWS_ACCOUNT_NUMBER --image /mnt/centos-linux-7.img --destination /mnt/bundle
ec2-upload-bundle --access-key $AWS_ACCESS_KEY --secret-key $AWS_SECRET_KEY --bucket $AWS_AMI_BUCKET --manifest /mnt/bundle/$AWS_AMI_BUCKET.manifest.xml --debug --retry
