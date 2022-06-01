#/bin/bash

copy_media () {

    echo "check file $1"

    if [ ! -f "/images/$1" ] 
    then
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@10.0.10.56:media/$1 /images
        chmod -R a+rwx /images/$1
    else
        echo "file $1 still exists"
    fi
      
} 

# copy some files

copy_media SLE-15-SP2-Full-x86_64-GM-Media1.iso

sudo zypper clean
sudo zypper refresh

# Root.sh Failed With error "CLSRSC-317: FAILED To Register Oracle OHASD Service" on SLES15 SP1 (Doc ID 2714093.1)
# sudo mv /etc/rc.d /etc/rc.d_bak
sudo zypper --non-interactive in insserv-compat

# install some packages
# xauth
sudo zypper --non-interactive install xauth
sudo zypper --non-interactive install xdpyinfo

sudo zypper --non-interactive in libgcc_s1-32bit libcap-devel libcap2 libXext-devel libcap2-32bit libcap-ng-utils libcap-ng0-32bit libXtst6-32bit nfs-kernel-server
sudo zypper --non-interactive in libpcre1-32bit libpcre16-0 libpcre2-16-0
sudo zypper --non-interactive in libjpeg62 libjpeg8 libXrender-devel libXrender1-32bit libXi-devel libXi6-32bit libstdc++-devel smartmontools
sudo zypper --non-interactive in libstdc++6-32bit libtiff5
sudo zypper --non-interactive in gcc-c++ gcc-32bit gcc-c++-32bit
sudo zypper --non-interactive in libgfortran4 libaio1-32bit
sudo zypper --non-interactive in rdma-core rdma-core-devel
sudo zypper --non-interactive in libpng16-16-32bit pixz 
sudo zypper --non-interactive in oracle_server
sudo zypper --non-interactive in patterns-server-enterprise-oracle_server
# for priv escalation
sudo zypper --non-interactive in acl

# legacy package
sudo zypper --non-interactive in libcap1 libcap1-32bit

# http://ftp5.gwdg.de/pub/opensuse/repositories/home:/ithod:/restored/openSUSE_Leap_42.3/x86_64/libstdc++33-3.3.3-35.1.x86_64.rpm   
# copied before
# sudo zypper --non-interactive in /root/libstdc++33-3.3.3-35.1.x86_64.rpm

# for rlwrap
sudo zypper --non-interactive in readline-devel autoconf automake libtool 
# for git
sudo zypper --non-interactive in git

# fio dstat
sudo zypper --non-interactive in fio dstat hdparm nvme-cli


if [ -f "/etc/profile.d/oracle.sh" ] 
    then
        sudo rm /etc/profile.d/oracle.sh
fi


if [ -f "/etc/profile.d/oracle.csh" ] 
    then
        sudo rm /etc/profile.d/oracle.csh
fi

# for testing
# need to implement dns
# fixed with ansible

## todd



#    https://github.com/hanslub42/rlwrap

#Unzip and install the software using the following commands.

#gunzip rlwrap*.gz
#tar -xvf rlwrap*.tar
#cd rlwrap*
#./configure
#make
#make check
#make install