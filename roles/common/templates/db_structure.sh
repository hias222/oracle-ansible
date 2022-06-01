#/bin/bash

if [ ! -d "{{ db.oracle_home }}" ] 
then
   echo "create {{ db.oracle_home }}"
   mkdir -p {{ db.oracle_home }}
fi

cd {{ db.oracle_home }}

if [ ! -f "{{ db.oracle_home }}/runInstaller" ] 
then
unzip /images/{{ db.oracle_db_zip }} > /dev/null
else
    echo "{{ db.oracle_home }} existing files"
fi

rm -rf OPatch
unzip -o /images/{{ common.opatch_zip }} > /dev/null

# unzip -o /images/{{ db.oracle_db_ru }} -d {{ common.patch_dir}}  > /dev/null

#ASM HOME
#/orasw/oracrs/product/crs19

{{ db.oracle_home }}/runInstaller -responseFile {{ common.oracle_base }}/software_db.rsp -silent -ignorePrereqFailure

#todo
#/orasw/oracle/product/db19/root.sh