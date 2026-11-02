#!/bin/bash
# Starts the default Database Resident Connection Pool (DRCP) used by the
# tests that connect with SERVER=POOLED.
sqlplus -s / as sysdba <<'SQL' > /dev/null
begin
  dbms_connection_pool.start_pool();
exception
  when others then
    -- ORA-56501: the pool has already been started
    if sqlcode != -56501 then raise; end if;
end;
/
SQL
echo "DRCP pool started"
