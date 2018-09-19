#!bin/sh

#Nested Virtualization Packer Agent Install Script
#Install packages required 
   
#Install QEMU/KVM:
sudo yum install -y qemu-kvm unzip git

#Packer needs __qemu-kvm__ available in the BASH path. For some reason it isn't added. Add it:

echo 'export PATH=$PATH:/usr/libexec' > /etc/profile.d/libexec-path.sh

source /etc/profile.d/libexec-path.sh

#Also, add __/usr/local/bin__ to your BASH path:

echo 'export PATH=$PATH:/usr/local/bin' > /etc/profile.d/usr-local-bin-path.sh

source /etc/profile.d/usr-local-bin-path.sh

#Download the [latest version of Packer](https://www.packer.io/downloads.html):

curl -O https://releases.hashicorp.com/packer/1.3.0/packer_1.3.0_linux_amd64.zip

#Unzip __packer__:

unzip packer_1.3.0_linux_amd64.zip

#There's already a program named __packer__ in the BASH path. Do not remove this program as it is part of the __cracklib-dicts__ package which many other programs depend on. Instead, rename the __packer__ program you just downloaded to __packerio__:

mv packer /usr/local/
sudo ln -s /usr/local/packer /usr/bin/packer.io

#Install Java libraries for Jenkins agent:

sudo yum install java-1.8.0-openjdk-devel -y
#sudo yum install java-1.7.0-openjdk -y
