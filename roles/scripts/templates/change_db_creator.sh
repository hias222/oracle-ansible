#!/bin/bash

# script must be run in db_creator_19 dir

# Original we have files from 1-8
# With dbca we have 1-10 without 2

# sed -i 's#set newname for datafile 2 to new;#set newname for datafile 10 to new;#g' cr_cdb.bash

chmod u+x *.bash

sed -i 's#DB_HOST=$(uname -n)db#DB_HOST=$(uname -n)#g' cr_dg.bash
sed -i 's#SSH_CONECTIVITY=false#SSH_CONECTIVITY=true#g' cr_dg.bash

sed -i 's#DB_HOST=$(uname -n)db#DB_HOST=$(uname -n)#g' change_logfile_size.bash
sed -i 's#SSH_CONECTIVITY=false#SSH_CONECTIVITY=true#g' change_logfile_size.bash