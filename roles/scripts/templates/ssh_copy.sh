#/bin/bash

fct_usage()
{
echo -e "
$0 <DB_NAME>

Usage:
\t<FILE> = file to copy from ssh
"
}

if [[ $# != 1 ]];then
 fct_usage
 exit 1
fi

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

copy_media $1
