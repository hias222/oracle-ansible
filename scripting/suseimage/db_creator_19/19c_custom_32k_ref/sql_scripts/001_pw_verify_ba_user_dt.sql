-- Passwort-Check fuer BA-User gemaess BA-Richtlinien
-- gsi 29.7.2015
--
-- mindestens 8 Zeichen
-- mindestens 1 Zahl
-- mindestens 1 Sonderzeichen
-- mindestens 1 Grossbuchstabe
-- mindestens 1 Kleinbuchstabe
-- Add_on:
-- Passwort nicht gleich User-Id   
--> funktioniert nicht weil create/alter user die User-ID in GROSSBUCHSTABEN uebergibt
-- Passwort nicht gleich altem Passwort  
--> wird schon vom profile abgefangen, nicht notwendig in der Funktion
-- Passwort muss sich in mindestens 3 Stellen vom alten Passwort unterscheiden 
--> funktioniert nicht weil create/alter user das alte Passwort nicht uebergibt!!!!

set serveroutput on;

CREATE OR REPLACE FUNCTION pw_verify_ba_user (
   username IN VARCHAR2,
   password IN VARCHAR2,
   old_password IN VARCHAR2)
   RETURN BOOLEAN
   IS
	chararraylower    	VARCHAR2(52);
	chararrayupper    	VARCHAR2(52);
	differ       		INTEGER;
	digitarray   		VARCHAR2(20);
	ischarlower  		BOOLEAN;
	ischarupper  		BOOLEAN;
	isdigit      		BOOLEAN;
	ispunct      		BOOLEAN;
	m            		INTEGER;
	n            		BOOLEAN;
	punctarray   		VARCHAR2(25);
 
BEGIN
   digitarray := '0123456789';
   chararraylower := 'abcdefghijklmnopqrstuvwxyz';
   chararrayupper := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
   punctarray := '!"#$%&()''*+,-/:;<=>?_';
 
   -- check for password identical with userid
   IF password = username THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort ist identisch zur User-Id');
      raise_application_error(-20001, 'Das Passwort ist identisch zur User-Id');
   END IF;
 
   -- check for new password identical with old password
   IF UPPER(password) = UPPER(old_password) THEN
      DBMS_OUTPUT.PUT_LINE('--> Das neue Passwort muss sich vom alten Passwort unterscheiden');
      raise_application_error(-20002, 'Das neue Passwort muss sich vom alten Passwort unterscheiden');
   END IF;
 
   -- check for minimum password length
   IF LENGTH(password) < 8 THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort muss aus mindestens 8 Zeichen bestehen');
      raise_application_error(-20003, 'Das Passwort muss aus mindestens 8 Zeichen bestehen',FALSE);
   END IF;

   <<finddigit>>
   isdigit := FALSE;
   m := LENGTH(password);
 
   FOR i IN 1..10 LOOP
      FOR j IN 1..m LOOP
         IF SUBSTR(password,j,1) = SUBSTR(digitarray,i,1) THEN
            isdigit := TRUE;
            GOTO findcharlower;
         END IF;
      END LOOP;
   END LOOP;
 
   IF isdigit = FALSE THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort muss mindestens 1 Ziffer enthalten');
      raise_application_error(-20004, 'Das Passwort muss mindestens 1 Ziffer enthalten');
   END IF;
 
   <<findcharlower>>
   ischarlower := FALSE;
   FOR i IN 1..LENGTH(chararraylower) LOOP
      FOR j IN 1..m LOOP
         IF SUBSTR(password,j,1) = SUBSTR(chararraylower,i,1) THEN
            ischarlower := TRUE;
            GOTO findcharupper;
         END IF;
      END LOOP;
   END LOOP;
 
   IF ischarlower = FALSE THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort muss mindestens einen Kleinbuchstaben enthalten');
      raise_application_error(-20005, 'Das Passwort muss mindestens einen Kleinbuchstaben enthalten');
   END IF;

 <<findcharupper>>
   ischarupper := FALSE;
   FOR i IN 1..LENGTH(chararrayupper) LOOP
      FOR j IN 1..m LOOP
         IF SUBSTR(password,j,1) = SUBSTR(chararrayupper,i,1) THEN
            ischarupper := TRUE;
            GOTO findpunct;
         END IF;
      END LOOP;
   END LOOP;

   IF ischarupper = FALSE THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort muss mindestens einen Grossbuchstaben enthalten');
      raise_application_error(-20006, 'Das Passwort muss mindestens einen Grossbuchstaben enthalten');
   END IF;

 
   <<findpunct>>
   ispunct := FALSE;
   FOR i IN 1..LENGTH(punctarray) LOOP
      FOR j IN 1..m LOOP
         IF SUBSTR(password,j,1) = SUBSTR(punctarray,i,1) THEN
            ispunct := TRUE;
            GOTO endsearch;
         END IF;
      END LOOP;
   END LOOP;
 
   IF ispunct = FALSE THEN
      DBMS_OUTPUT.PUT_LINE('--> Das Passwort muss mindestens 1 Sonderzeichen enthalten');
      raise_application_error(-20007, 'Das Passwort muss mindestens 1 Sonderzeichen enthalten');
   END IF;      
 
   <<endsearch>>
   -- Make sure new password differs from old by at least three characters
   IF old_password = '' THEN
      raise_application_error(-20008, 'Das alte Passwort ist leer');
   END IF;
 
   differ := LENGTH(old_password) - LENGTH(password);
   IF ABS(differ) < 3 THEN
      IF LENGTH(password) < LENGTH(old_password) THEN
         m := LENGTH(password);
      ELSE
         m := LENGTH(old_password);
      END IF;
 
      differ := ABS(differ);
 
      FOR i IN 1..m LOOP
         IF SUBSTR(password,i,1) != SUBSTR(old_password,i,1) THEN
            differ := differ + 1;
         END IF;
      END LOOP;
 
      IF differ < 3 THEN
         DBMS_OUTPUT.PUT_LINE('--> Die Passworte muessen sich mindestens in 3 Stellen unterscheiden');
         raise_application_error(-20009, 'Die Passworte muessen sich mindestens in 3 Stellen unterscheiden');
      END IF;
   END IF;
   -- Everything is fine; return TRUE
   DBMS_OUTPUT.PUT_LINE('--> Das Passwort entspricht den BA-Richtlinien');
   RETURN(TRUE);

--EXCEPTION WHEN OTHERS THEN
--  RETURN(FALSE);
END;
/
