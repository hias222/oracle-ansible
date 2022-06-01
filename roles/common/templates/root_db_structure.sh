#/bin/bash

if [ ! -d "/images" ] 
then
   sudo mkdir /images
   sudo chmod -R a+rwx /images
fi

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

copy_media {{ db.oracle_db_zip }}
#copy_media {{ db.oracle_db_ru }}
copy_media {{ common.opatch_zip }}
copy_media {{ db.db_creator_data }}


if [ ! -d "{{ grid.user_home}}/.ssh" ] 
then
   echo "create {{ grid.user_home}}/.ssh"
   sudo mkdir {{ grid.user_home}}/.ssh
   sudo chown oracle:oinstall {{ grid.user_home}}/.ssh
   sudo chmod 0700 {{ grid.user_home}}/.ssh
fi

#ASM HOME
#/orasw/oracrs/product/crs19