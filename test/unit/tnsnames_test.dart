import 'dart:io';

import 'package:oracledb_dart/src/connect_params.dart';
import 'package:oracledb_dart/src/tnsnames.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tns');
    File('${dir.path}/tnsnames.ora').writeAsStringSync('''
# comment
SALES, sales_alias =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = db1.example.com)(PORT = 1522))
    (CONNECT_DATA = (SERVICE_NAME = sales.example.com))
  )

hr=(DESCRIPTION=(ADDRESS=(PROTOCOL=tcps)(HOST=db2)(PORT=2484))(CONNECT_DATA=(SERVICE_NAME=hr))(SECURITY=(SSL_SERVER_CERT_DN="CN=db2,O=Example")))
IFILE = extra.ora
''');
    File('${dir.path}/extra.ora').writeAsStringSync(
        'extra = (DESCRIPTION=(ADDRESS=(HOST=db3)(PORT=1521))'
        '(CONNECT_DATA=(SID=orcl)))\n');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('parses entries, aliases and included files', () {
    final entries = parseTnsNames(File('${dir.path}/tnsnames.ora'));
    expect(entries.keys, containsAll(['SALES', 'SALES_ALIAS', 'HR', 'EXTRA']));
    expect(entries['SALES'], contains('(HOST=db1.example.com)'));
  });

  test('resolves aliases to connection parameters', () {
    final sales = ConnectParams.fromDsn('sales', configDir: dir.path);
    expect(sales.host, 'db1.example.com');
    expect(sales.port, 1522);
    expect(sales.serviceName, 'sales.example.com');
    final hr = ConnectParams.fromDsn('HR', configDir: dir.path);
    expect(hr.usesTls, isTrue);
    expect(hr.sslServerCertDn, 'CN=db2,O=Example');
    expect(ConnectParams.fromDsn('extra', configDir: dir.path).sid, 'orcl');
    expect(() => ConnectParams.fromDsn('missing', configDir: dir.path),
        throwsA(anything));
  });

  test('Easy Connect strings', () {
    final p = ConnectParams.fromDsn(
        'tcps://host.example.com/svc?ssl_server_dn_match=off&sdu=16384');
    expect(p.usesTls, isTrue);
    expect(p.port, 2484);
    expect(p.sslServerDnMatch, isFalse);
    expect(p.sdu, 16384);
    final q = ConnectParams.fromDsn('[::1]:1600/svc:pooled');
    expect(q.host, '::1');
    expect(q.port, 1600);
    expect(q.serverType, 'pooled');
  });
}
