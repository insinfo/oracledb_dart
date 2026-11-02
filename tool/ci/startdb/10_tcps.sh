#!/bin/bash
# Configures a TCPS listener on port 2484 using the wallet created by
# tool/ci/create_tcps_wallet.sh (mounted at /share).
# Runs on every container start (gvenzl /container-entrypoint-startdb.d).
# The wallet is created outside the container with oraclepki,
# since the slim image has no Java/PKI libraries.
WALLET=/opt/oracle/oradata/tcps_wallet
ADMIN=$ORACLE_HOME/network/admin
if [ ! -f /share/tcps_wallet/cwallet.sso ]; then
  echo "TCPS wallet not found in /share/tcps_wallet; TCPS not configured"
  exit 0
fi
mkdir -p $WALLET
cp /share/tcps_wallet/cwallet.sso /share/tcps_wallet/ewallet.p12 $WALLET/
chmod 600 $WALLET/*

cat > $ADMIN/listener.ora <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC_FOR_FREE))
      (ADDRESS = (PROTOCOL = TCP)(HOST=)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCPS)(HOST=)(PORT = 2484))
    )
  )

DEFAULT_SERVICE_LISTENER = FREE
WALLET_LOCATION = (SOURCE = (METHOD = FILE)(METHOD_DATA = (DIRECTORY = $WALLET)))
SSL_CLIENT_AUTHENTICATION = FALSE
EOF

cat > $ADMIN/sqlnet.ora <<EOF
NAMES.DIRECTORY_PATH = (EZCONNECT, TNSNAMES)
# See https://github.com/gvenzl/oci-oracle-xe/issues/43
DISABLE_OOB=ON
BREAK_POLL_SKIP=1000
WALLET_LOCATION = (SOURCE = (METHOD = FILE)(METHOD_DATA = (DIRECTORY = $WALLET)))
SSL_CLIENT_AUTHENTICATION = FALSE
EOF

lsnrctl stop > /dev/null 2>&1 || true
lsnrctl start > /dev/null
sqlplus -s / as sysdba <<'SQL' > /dev/null
alter system register;
SQL
echo "TCPS listener configured on port 2484"
