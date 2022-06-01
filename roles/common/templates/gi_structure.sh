#/bin/bash

if [ ! -d "{{ grid.oracle_home }}" ] 
then
   echo "create {{ grid.oracle_home }}"
   mkdir -p {{ grid.oracle_home }}
fi

cd {{ grid.oracle_home }}

if [ ! -f "{{ grid.oracle_home }}/gridSetup.sh" ] 
then
unzip /images/{{ grid.oracle_grid_zip }} > /dev/null
else
    echo "{{ grid.oracle_home }} existing files"
fi

rm -rf OPatch
unzip /images/{{ common.opatch_zip }} > /dev/null

echo "{{ grid.oracle_home }}/gridSetup.sh -responseFile {{ common.oracle_base }}/grid.rsp -silent -ignorePrereqFailure"
{{ grid.oracle_home }}/gridSetup.sh -responseFile {{ common.oracle_base }}/software_grid.rsp -silent -ignorePrereqFailure 

#ASM HOME
#/orasw/oracrs/product/crs19