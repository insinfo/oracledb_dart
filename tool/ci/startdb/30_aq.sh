#!/bin/bash
# Grants the test user the privileges used by the Advanced Queuing tests.
sqlplus -s / as sysdba <<'SQL' > /dev/null
alter session set container = FREEPDB1;
grant aq_administrator_role, aq_user_role to dart_user;
grant execute on dbms_aq to dart_user;
grant execute on dbms_aqadm to dart_user;
SQL
echo "AQ privileges granted"
