

CREATE TABLESPACE poc DATAFILE SIZE 1t;
alter tablespace poc autoextend on NEXT 100g
maxsize unlimited;

create user poc identified by Start1234 DEFAULT TABLESPACE poc quota unlimited on poc;
grant dba to poc;
grant connect to poc;
