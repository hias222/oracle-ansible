# asm

## NVME

7361456_ICRPC2DD2ORA6.4T

<https://www.linkedin.com/pulse/linux-nvme-cli-cheat-sheet-frank-ober/?articleId=6716806835506176000>

nvmeadm list -v

### Seeing what nvme drive features exist on your drive and firmware version

nvme id-ctrl /dev/nvme0n1 -H | more

### Checking the health of your nvme SSD.

nvme smart-log /dev/nvme0n1

### namespace

nvme list

```bash
Node             SN                   Model                                    Namespace Usage                      Format           FW Rev
---------------- -------------------- ---------------------------------------- --------- -------------------------- ---------------- --------
/dev/nvme0n1     PHLN9354024P6P4CGN   7361456_ICRPC2DD2ORA6.4T                 1           6.40  TB /   6.40  TB    512   B +  0 B   VDV1RL04
```

nvme id-ns /dev/nvme0 --namespace-id=0x1

```bash
NVME Identify Namespace 1:
nsze    : 0x2e93432b0
ncap    : 0x2e93432b0
nuse    : 0x2e93432b0
nsfeat  : 0
nlbaf   : 1
flbas   : 0
mc      : 0
dpc     : 0
dps     : 0
nmic    : 0
rescap  : 0
fpi     : 0
dlfeat  : 0
nawun   : 0
nawupf  : 0
nacwu   : 0
nabsn   : 0
nabo    : 0
nabspf  : 0
noiob   : 0
nvmcap  : 6401252745216
nsattr	: 0
nvmsetid: 0
anagrpid: 0
endgid  : 0
nguid   : 01000000210000005cd2e41381135151
eui64   : 5cd2e41381132000
lbaf  0 : ms:0   lbads:9  rp:0x2 (in use)
lbaf  1 : ms:0   lbads:12 rp:0
```

nvme detach-ns /dev/nvme0 -namespace-id=1 -controllers=0
nvme delete-ns /dev/nvme0 -namespace-id=1

nvme create-ns /dev/nvme0 -nsze 11995709440 -ncap 1199570940 -flbas 0 -dps 0 -nmic 0
nvme create-ns /dev/nvme0 -nsze 0x2e93432b0 -ncap 0x2e93432b0 -flbas 0 -dps 0 -nmic 0
nvme create-ns /dev/nvme0 -nsze 0x1749A1958 -ncap 0x1749A1958 -flbas 0 -dps 0 -nmic 0
nvme create-ns /dev/nvme0 -nsze 0x16A800000 -ncap 0x16A800000 -flbas 0 -dps 0 -nmic 0
nvme attach-ns /dev/nvme0 -namespace-id=1 -controllers=0

6251223384
6251220000
0x1749A0C20

echo 1 > /sys/class/nvme/nvme0/rescan_controller
echo 1 > /sys/class/nvme/nvme0/reset_controller