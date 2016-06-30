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
#    $ vagrant up
#

require 'openssl'

Vagrant.configure(2) do |config|
  config.vm.box = "centos/6"
  config.vm.provider "virtualbox"

  # Start set-up.
  system "clear"

  puts <<-EOF
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

  def error(message)
    puts "\n\033[0;31m#{message}\033[0m"
    sleep 1
    system "clear"
  end

  def notice(message)
    puts "\033[1m#{message}\033[0m\n"
    sleep 1
  end

  while true do
    print "Ready to get started? [Y/n] "

    line = STDIN.gets.chomp
    case line

    when "y", "Y"
      sleep 1
      system "clear"
      break
    when "n", "N"
      puts "Aborted.."
      exit
    end
  end

  # Prompt EC2_CERT value.
  while true do
    puts "Enter the contents of your X.509 EC2 certificate below: "

    $/ = "-----END CERTIFICATE-----"

    data = STDIN.gets

    # Validate the certificate.
    begin
      cert = OpenSSL::X509::Certificate.new data
    rescue
      error "The certificate entered is not valid."
      next
    end

    EC2_CERT = data

    system "clear"
    break
  end

  # Get EC2_PRIVATE_KEY value.
  while true do
    puts "Enter the contents your X.509 EC2 private key below: "

    $/ = "-----END CERTIFICATE-----"

    data = STDIN.gets

    # Validate the certificate.
    begin
      cert = OpenSSL::X509::Certificate.new data
    rescue
      error "The private key entered is not valid."
      next
    end

    EC2_PRIVATE_KEY = data

    system "clear"
    break
  end

  # Prompt AWS_ACCOUNT_NUMBER value.
  while true do
    print "Enter your AWS account number: "

    line = STDIN.gets.chomp

    if line !~ /^[0-9\-]{8,15}$/
      error "The account number entered is not valid."
      next
    else
      AWS_ACCOUNT_NUMBER = system "echo #{line} | tr -d '-'"

      system "clear"
      break
    end
  end

  # Prompt AWS_ACCESS_KEY value.
  while true do
    print "Enter your AWS access key: "

    line = STDIN.gets.chomp

    if line !~ /^[A-Z0-9]{20}$/
      error "The access key entered is not valid."
      next
    else
      AWS_ACCESS_KEY = line

      system "clear"
      break
    end
  end

  # Prompt AWS_SECRET_KEY value.
  while true do
    print "Enter your AWS secret key: "

    line = STDIN.gets.chomp

    if line !~ /^[a-zA-Z0-9\+\/]{39,40}$/
      error "The secret key entered is not valid."
      next
    else
      AWS_SECRET_KEY = line

      system "clear"
      break
    end
  end

  # Prompt AWS_S3_BUCKET value.
  while true do
    print "Enter your AWS S3 bucket: "

    if line !~ /^[^\.\-]?[a-zA-Z0-9\.\-]{1,63}[^\.\-]?$/
      error "The bucket name entered is not valid."
      next
    else
      AWS_S3_BUCKET = line

      system "clear"
      break
    end
  end

  # Prompt EC2_REGION, set REGION/PV_GRUB values.
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

    line = STDIN.gets.chomp
    case line

    when 1
      EC2_REGION="us-east-1"
      AKI_KERNEL="aki-919dcaf8"
    when 2
      EC2_REGION="us-west-1"
      AKI_KERNEL="aki-880531cd"
    when 3
      EC2_REGION="us-west-2"
      AKI_KERNEL="aki-fc8f11cc"
    when 4
      EC2_REGION="eu-west-1"
      AKI_KERNEL="aki-919dcaf8"
    when 5
      EC2_REGION="eu-central-1"
      AKI_KERNEL="aki-919dcaf8"
    when 6
      EC2_REGION="ap-northeast-1"
      AKI_KERNEL="aki-176bf516"
    when 7
      EC2_REGION="ap-northeast-2"
      AKI_KERNEL="aki-01a66b6f"
    when 8
      EC2_REGION="ap-southeast-1"
      AKI_KERNEL="aki-503e7402"
    when 9
      EC2_REGION="ap-southeast-2"
      AKI_KERNEL="aki-c362fff9"
    when 10
      EC2_REGION="sa-east-1"
      AKI_KERNEL="aki-5553f448"
    else
      error "Not a valid entry."
      next
    end

    if EC2_REGION != ""
      sleep 1
      system "clear"
      break
    end
  end

  notice "Writing the configuration to: ~/.aws"

  config.vm.provision "shell", inline: <<-EOF
    cat << STDOUT > ~/.aws

export AMI_BUNDLR_ROOT="~/ec2-ami-bundlr"

# Amazon EC2 account.
export AWS_ACCOUNT_NUMBER=#{AWS_ACCOUNT_NUMBER}
export AWS_ACCESS_KEY=#{AWS_ACCESS_KEY}
export AWS_SECRET_KEY=#{AWS_SECRET_KEY}
export AWS_S3_BUCKET=#{AWS_S3_BUCKET}

export EC2_CERT=#{BUILD_KEYS_DIR}/cert.pem
export EC2_PRIVATE_KEY=#{BUILD_KEYS_DIR}/pk.pem
export EC2_REGION=#{EC2_REGION}

# Amazon EC2 Tools.
export EC2_HOME=#{BUILD_TOOLS_DIR}
export JAVA_HOME=/usr
export PATH=$PATH:$EC2_HOME/bin:$BUILD_TOOLS_DIR/bin
STDOUT

    sh ~/sync/ec2-ami-bundlr.sh
  EOF
end