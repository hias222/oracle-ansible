# DB Creator

## Golden Image

"Golden Image" - Backup  

Die Datenbank die als Referenz benutzt wird, muss folgendes enthalten:

* BA_User Profile inkl. BA_verify_function müssen in der Referenzdatenbank enthalten sein.
* Database Optionen: DB-Vault, Oracle Text, JAVA, Lable Security müssen in der CDB$ROOT aber nicht in der PDB$SEED installiert sein.
* Der Name der Referenzdatenbank sollte wenn möglich "cdbseed" sein, dann muss nicht zu viel im DB-CREATOR angepasst werden.
* Um das "golden Image" klein zu halten sollten alle Tablespaces/Datafiles so klein wie möglich gehalten werden und im DB-CREATOR als Nachlaufskript dann vergrößert werden. (Resize der Tablespaces/Datafiles in der Referenzdatenbank vor dem Backup)
Die Referenzdatenbank sollte nur aus 8 Datafiles bestehen. Ansonsten muss im DB-CREATOR Anpassungen vorgenommen werden.
(CDB$ROOT:SYSTEM,SYSAUX,UNDO,USERS;  
PDB$SEED:SYSTEM,SYSAUX,UNDO,USERS).  
* Für den DB-CREATOR wird ein "Laufzeit" Controlfile der Referenzdatenbank benötigt. Also einfach ein cp /oracle/ora12c/cdbseed/controlfile/control1.ctl <Ziel-Ort(/resources)> ausführen, wenn die Referenzdatenbank offline ist und anschließend in ctl_cdbseed.ctl umbenennen
* In der Referenzdatenbank muss bevor sie "gebackupt" wird der DB-Vault disabled werden. (Muss ohne Vault Konfiguration und ohne User erstellt werden -> Diese Abschnitte müssen beim Erstellen der Referenzdatenbank vorher im Skript aus kommentiert werden. Außerdem darauf achten, dass die Referenz DB je nach Version mit parameter Compatible=19.0.0 oder 20.0.0 oder 21.0.0 etc installiert ist und dieses auch im späteren Creator beibehalten wird. )  
* Um den DB-CREATOR in seiner Laufzeit möglichst kurz zu halten, sollte das "golden Image" von einem System gemacht werden das den aktuellen ZELOS stand enthält.  
Man hat die Möglichkeit eine Ref-DB(ohne Vault und User) aus dem Backup zu klonen und dann auf die neue Version zu patchen, oder man installiert eine Ref-DB mit dem Custom Creator, welchen man vorher an neue Version angepasst hat. Für beide Varianten liegen die Skripte unter /zfs/fuchss/zelos_db_creator_19_refs. Wird ein 32k Backup benötigt, zb für einen automatischen Zelos creator, muss das Custom Skript verwendet werden (Backups mit jeweiliger Blocksize in das skript /zfs/fuchs/zelos_creator_pasolfora_7.3 einpflegen bzw Skript anpassen) . l9937022 kann als Host für diese Installationen verwendet werden.

```bash
rman target /
CONFIGURE COMPRESSION ALGORITHM 'BASIC';
CONFIGURE DEVICE TYPE disk PARALLELISM 4;
shutdown immediate;
startup mount;
RUN
{
ALLOCATE CHANNEL ch11 TYPE DISK;
ALLOCATE CHANNEL ch12 TYPE DISK;
ALLOCATE CHANNEL ch13 TYPE DISK;
ALLOCATE CHANNEL ch14 TYPE DISK;
backup as compressed backupset database
FORMAT '/opt/oracle/temp/datafiles/%d_D_%T_%u_s%s_p%p'
CURRENT CONTROLFILE FORMAT '/opt/oracle/temp/ctl_cdbseed.bkp'
SPFILE FORMAT '/opt/oracle/temp/spfile_cdbseed.bkp';
}
alter database open;
 
Beispiel:
rman target /
CONFIGURE COMPRESSION ALGORITHM 'BASIC'; 
CONFIGURE DEVICE TYPE disk PARALLELISM 4;
shutdown immediate;
startup mount;
RUN
{
ALLOCATE CHANNEL ch11 TYPE DISK;
ALLOCATE CHANNEL ch12 TYPE DISK;
ALLOCATE CHANNEL ch13 TYPE DISK;
ALLOCATE CHANNEL ch14 TYPE DISK;
backup as compressed backupset database
FORMAT '/home/oracle/fuchss/db_creator_19_73/19c_default/resources/datafiles/%d_D_%T_%u_s%s_p%p'
CURRENT CONTROLFILE FORMAT '/home/oracle/fuchss/db_creator_19_73/19c_default/resources/ctl_cdbseed.bkp'
SPFILE FORMAT '/home/oracle/fuchss/db_creator_19_73/19c_default/resources/spfile_cdbseed.bkp';
}
```