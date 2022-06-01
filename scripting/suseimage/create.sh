#!/bin/bash
cd db_creator_19
rm ../../../../ansible/roles/common/files/db_creator_19.tar.gz 
tar -cvzf ../../../../ansible/roles/common/files/db_creator_19.tar.gz *
