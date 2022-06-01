#!/bin/bash
# sudo ./onessd.sh 3 /dev/nvme0n1 4k
# dstat -pcmrd
# sudo hdparm /dev/nvme0n1
# lspci | grep Root
#
# ./onessd.sh 3 /dev/nvme0n1 4k

[ $# -ne 3 ] && echo Usage $0 numjobs /dev/DEVICENAME BLOCKSIZE && exit 1

fio --readonly --name=onessd \
    --filename=$2 \
    --filesize=100g --rw=randread --bs=$3 --direct=1 --overwrite=0 \
    --numjobs=$1 --iodepth=32 --time_based=1 --runtime=3600 \
    --ioengine=io_uring \
    --registerfiles --fixedbufs \
    --gtod_reduce=1 --group_reporting