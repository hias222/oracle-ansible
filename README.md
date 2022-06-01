# Ansible

## git

first prepare key in git

git clone git@10.0.10.56:dataguard/ansible.git

## ansible 

zypper addrepo https://download.opensuse.org/repositories/systemsmanagement/SLE_15_SP2/systemsmanagement.repo
zypper refresh
zypper install ansible

sudo zypper install python3-pip
sudo pip uninstall ansible
sudo pip install ansible

sudo pip install --upgrade pip

pygobject 3.34.0 requires pycairo>=1.11.1, which is not installed.
## Konfiguration

in production host configure keys and hosts
Change the key pathes
## Start

check
ansible-playbook -i production/hosts site.yml --check

Run
ansible-playbook -i production/hosts site.yml 

only one host
ansible-playbook -i production/hosts site.yml --limit host1

after force reboot
ansible-playbook -i production/hosts nic.yml --limit l9701022

script fast
ansible-playbook -i production/hosts scripts.yml --limit l9701022 -e fast_install=true

files
out of db_creator_19
tar -cvzf ../../../../ansible/roles/scripts/files/db_creator_19.tar.gz *
tar -cvzf ../../../../ansible/roles/scripts/files/sync.tar.gz * 

## same addons

### ASM

```bash
sqlplus / as sysasm
create diskgroup dg2 external redundancy disk '/dev/sdc' name dg2;
create diskgroup dg3 external redundancy disk '/dev/sdd' name dg3;

-- ALTER DISKGROUP dg2 MOUNT;
-- ALTER DISKGROUP dg3 MOUNT;
```

### dbcreator remove 

echo "###[STEP]### enabling RAC" 

#Server 2