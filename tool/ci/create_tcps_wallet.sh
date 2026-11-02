#!/usr/bin/env bash
# Creates the files needed to test TCPS connections against an Oracle
# Database container:
#
#   <out>/share/tcps_wallet  server wallet (cwallet.sso), mounted at /share
#   <out>/client/ewallet.pem certificate authority trusted by the client
#
# Requires openssl, curl and java (the wallet is created with the orapki
# classes from the oraclepki jar published on Maven Central).
set -euo pipefail

out=${1:?usage: create_tcps_wallet.sh <output directory>}
pki_version=23.26.4.0.0
wallet_password=WalletPasswd123
mkdir -p "$out/pki" "$out/share/tcps_wallet" "$out/client"
out=$(cd "$out" && pwd)
cd "$out/pki"

# certificate authority and server certificate (macOS requires the
# serverAuth extended key usage and a validity of at most 825 days)
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem \
  -days 3650 -subj "/CN=oracledb_dart test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
  -subj "/CN=localhost" 2>/dev/null
printf '%s\n' 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  'extendedKeyUsage=serverAuth' 'basicConstraints=CA:FALSE' \
  'keyUsage=critical,digitalSignature,keyEncipherment' > server.ext
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 365 -out server.pem -extfile server.ext 2>/dev/null
openssl pkcs12 -export -in server.pem -inkey server.key -certfile ca.pem \
  -out server.p12 -passout pass:P12passwd123 \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# ORAPKI_JAR may point to an already downloaded jar
jar=${ORAPKI_JAR:-}
if [ -z "$jar" ]; then
  jar=$PWD/oraclepki-$pki_version.jar
  url=https://repo1.maven.org/maven2/com/oracle/database/security/oraclepki/$pki_version/oraclepki-$pki_version.jar
  curl -sSfL --retry 5 -o "$jar" "$url"
  echo "$(curl -sSfL --retry 5 "$url.sha1")  $jar" | shasum -a 1 -c - >/dev/null
fi

pki() { java -cp "$jar" oracle.security.pki.textui.OraclePKITextUI "$@"; }
wallet=$out/share/tcps_wallet
pki wallet create -wallet "$wallet" -pwd "$wallet_password" -auto_login >/dev/null
pki wallet import_pkcs12 -wallet "$wallet" -pwd "$wallet_password" \
  -pkcs12file server.p12 -pkcs12pwd P12passwd123 >/dev/null
cp ca.pem "$out/client/ewallet.pem"
chmod -R a+rX "$out/share"
echo "wallet created in $wallet"
