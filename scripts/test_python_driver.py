import contextlib
import os
import sys

# Ensure the local python-oracledb source is on sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PYTHON_ORACLEDB_SRC = os.path.join(PROJECT_ROOT, 'python-oracledb', 'src')
if PYTHON_ORACLEDB_SRC not in sys.path:
    sys.path.insert(0, PYTHON_ORACLEDB_SRC)

import oracledb


def main():
    user = os.getenv('ORACLE_USER', 'dart_user')
    password = os.getenv('ORACLE_PASSWORD', 'dart')
    dsn = os.getenv('ORACLE_DSN', 'localhost:1521/XEPDB1')

    print(f'Connecting as {user}@{dsn} using local python-oracledb checkout...')
    with oracledb.connect(user=user, password=password, dsn=dsn) as conn:
        with conn.cursor() as cursor:
            cursor.execute('SELECT 1 FROM dual')
            result = cursor.fetchone()
            print('Query result:', result)


if __name__ == '__main__':
    trace_file = os.getenv('PYTHON_AUTH_TRACE_FILE')
    if trace_file:
        os.environ.setdefault('PYO_DEBUG_PACKETS', '1')
        with open(trace_file, 'w', encoding='ascii', buffering=1) as fh:
            with contextlib.redirect_stdout(fh):
                main()
        print(f'Pacotes Python registrados em {trace_file}')
    else:
        main()
