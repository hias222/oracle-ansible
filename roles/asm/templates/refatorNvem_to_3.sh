#!/bin/bash
# run as root

nvme id-ctrl /dev/nvme0 -H | grep 'NS Management'

nvme delete-ns /dev/nvme0 -namespace-id=1
nvme delete-ns /dev/nvme0 -namespace-id=2
nvme delete-ns /dev/nvme0 -namespace-id=3

nvme create-ns /dev/nvme0 -nsze 0xF6E00000 -ncap 0xF6E00000 -flbas 0 -dps 0 -nmic 0
nvme create-ns /dev/nvme0 -nsze 0xF6E00000 -ncap 0xF6E00000 -flbas 0 -dps 0 -nmic 0
nvme create-ns /dev/nvme0 -nsze 0xF6E00000 -ncap 0xF6E00000 -flbas 0 -dps 0 -nmic 0

nvme attach-ns /dev/nvme0 -namespace-id=1 -controllers=0
nvme attach-ns /dev/nvme0 -namespace-id=2 -controllers=0
nvme attach-ns /dev/nvme0 -namespace-id=3 -controllers=0

echo 1 > /sys/class/nvme/nvme0/rescan_controller
