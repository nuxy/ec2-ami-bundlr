# -*- mode: ruby -*-
# vi: set ft=ruby :

#
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
#    Vagrant 1.8.x
#    Virtualbox 5.x
#
#  Usage:
#    $ vagrant up | halt | ssh | destroy
#

def command(data = nil)
  Vagrant.configure(2) do |config|
    config.vm.box = "centos/6"
    config.vm.provider "virtualbox"

    if data
      config.vm.provision "shell", inline: data
      config.vm.provision "shell", path: "ec2-ami-bundlr.sh"
    end
  end
end

def error(message)
  puts "\n\033[0;31m#{message}\033[0m"
  sleep 1
  system "clear"
end

def setup()
  system "clear"

  print <<-EOF
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

  while true do
    print "Ready to get started? [Y/n] "

    case STDIN.gets.chomp
    when "y", "Y"
      sleep 1
      system "clear"
      break
    when "n", "N"
      puts "Aborted.."
      abort
    end
  end

  # Prompt EC2_CERT value.
  while true do
    puts "Enter the contents of your X.509 EC2 certificate below: "

    $/ = "-----END CERTIFICATE-----\n"

    data = STDIN.gets

    # Validate the certificate.
    begin
      OpenSSL::X509::Certificate.new data
    rescue
      error "The certificate entered is not valid."
      next
    end

    ec2_cert = data

    $/ = "\n"

    system "clear"
    break
  end

  # Get EC2_PRIVATE_KEY value.
  while true do
    puts "Enter the contents your X.509 EC2 private key below: "

    $/ = "-----END RSA PRIVATE KEY-----\n"

    data = STDIN.gets

    # Validate the certificate.
    begin
      OpenSSL::PKey::RSA.new data
    rescue
      error "The private key entered is not valid."
    next
    end

    ec2_private_key = data

    $/ = "\n"

    system "clear"
    break
  end

  # Prompt AWS_ACCOUNT_NUMBER value.
  while true do
    print "Enter your AWS account number: "

    line = STDIN.gets.chomp.delete("-")

    if line !~ /^[0-9]{8,15}$/
      error "The account number entered is not valid."
      next
    end

    aws_account_number = line

    system "clear"
    break
  end

  # Prompt AWS_ACCESS_KEY value.
  while true do
    print "Enter your AWS access key: "

    line = STDIN.gets.chomp

    if line !~ /^[A-Z0-9]{20}$/
      error "The access key entered is not valid."
      next
    end

    aws_access_key = line

    system "clear"
    break
  end

  # Prompt AWS_SECRET_KEY value.
  while true do
    print "Enter your AWS secret key: "

    line = STDIN.gets.chomp

    if line !~ /^[a-zA-Z0-9\+\/]{39,40}$/
      error "The secret key entered is not valid."
      next
    end

    aws_secret_key = line

    system "clear"
    break
  end

  # Prompt AWS_S3_BUCKET value.
  while true do
    print "Enter your AWS S3 bucket: "

    line = STDIN.gets.chomp

    if line !~ /^[^\.\-]?[a-zA-Z0-9\.\-]{1,63}[^\.\-]?$/
      error "The bucket name entered is not valid."
      next
    end

    aws_s3_bucket = line

    system "clear"
    break
  end

  # Prompt ec2_region, set REGION/PV_GRUB values.
  while true do

    puts <<-EOF
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

    print "Region [1-10] "

    case STDIN.gets.chomp
    when "1"
      ec2_region="us-east-1"
      aki_kernel="aki-919dcaf8"
    when "2"
      ec2_region="us-west-1"
      aki_kernel="aki-880531cd"
    when "3"
      ec2_region="us-west-2"
      aki_kernel="aki-fc8f11cc"
    when "4"
      ec2_region="eu-west-1"
      aki_kernel="aki-919dcaf8"
    when "5"
      ec2_region="eu-central-1"
      aki_kernel="aki-919dcaf8"
    when "6"
      ec2_region="ap-northeast-1"
      aki_kernel="aki-176bf516"
    when "7"
      ec2_region="ap-northeast-2"
      aki_kernel="aki-01a66b6f"
    when "8"
      ec2_region="ap-southeast-1"
      aki_kernel="aki-503e7402"
    when "9"
      ec2_region="ap-southeast-2"
      aki_kernel="aki-c362fff9"
    when "10"
      ec2_region="sa-east-1"
      aki_kernel="aki-5553f448"
    else
      error "Not a valid entry."
      next
    end

    system "clear"
    break
  end

  command <<-EOF
      cat << 'CONFIG' > ~/.aws
  export AMI_BUNDLR_ROOT=~/ec2-ami-bundlr

  # Amazon EC2 account.
  export AWS_ACCOUNT_NUMBER=#{aws_account_number}
  export AWS_ACCESS_KEY=#{aws_access_key}
  export AWS_SECRET_KEY=#{aws_secret_key}
  export AWS_S3_BUCKET=#{aws_s3_bucket}

  export AWS_KEYS_DIR=$AMI_BUNDLR_ROOT/keys
  export AWS_TOOLS_DIR=$AMI_BUNDLR_ROOT/tools

  export EC2_CERT=$AWS_KEYS_DIR/cert.pem
  export EC2_PRIVATE_KEY=$AWS_KEYS_DIR/pk.pem
  export EC2_REGION=#{ec2_region}

  # Amazon EC2 Tools.
  export EC2_HOME=$AWS_TOOLS_DIR
  export JAVA_HOME=/usr
  export PATH=$PATH:$EC2_HOME/bin:$AWS_TOOLS_DIR/bin
CONFIG
  EOF
end

# Support CLI arguments.
case ARGV[0]
when "up"
  setup
else
  command
end
