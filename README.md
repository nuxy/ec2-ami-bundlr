# EC2 AMI Bundlr

Create an Amazon EC2 machine image from a standard CentOS installation in a couple easy steps. Supports instance-store and paravirtual virtualization types. Can be run on Apple, Linux, and Windows with minimal dependencies.

## Supported Systems

This package currently supports Linux releases that are not dependent on the _Grub2_ bootloader and _Systemd_ init system. This will change in the near future.

- [CentOS](https://atlas.hashicorp.com/bento/boxes/centos-6.7)

## Dependencies

- [Vagrant](https://www.vagrantup.com/downloads.html) 1.8
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) 5

## Getting Started

    $ vagrant up

## License and Warranty

This package is distributed in the hope that it will be useful, but without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose.

*ec2-ami-bundlr* is provided under the terms of the [MIT license](http://www.opensource.org/licenses/mit-license.php)

## Maintainer

[Marc S. Brooks](https://github.com/nuxy)
