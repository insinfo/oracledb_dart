#C:\MyDartProjects\oracledb_dart\scripts\test_python_driver.py
import contextlib
import os
import sys
# para recompilar o driver e re-instalar apos instrumentação faça:
# cd .\python-oracledb\ 
# python -m pip install . --no-binary oracledb --force-reinstall

# Adicionei instrumentação direta no driver Python thin:
# python-oracledb/src/oracledb/impl/thin/messages/auth.pyx: logs detalhados em _process_return_parameters (num_params, chave/len/flags, session_data de interesse) e mensagens de transição para a fase 2.
# scripts/test_python_driver.py: continua com flags de debug; o cabeçalho do trace agora inclui as variáveis de ambiente relevantes.

# Ensure the local python-oracledb source is on sys.path
# --- COMENTE OU APAGUE ESTE BLOCO ---
# PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
# PYTHON_ORACLEDB_SRC = os.path.join(PROJECT_ROOT, 'python-oracledb', 'src')
# if PYTHON_ORACLEDB_SRC not in sys.path:
#     sys.path.insert(0, PYTHON_ORACLEDB_SRC)
# ------------------------------------

import oracledb


def main():
    user =  'dart_user'
    password =  'dart'
    dsn =  'localhost:1521/XEPDB1'

    # Forçar logs verbosos do lado Python (se suportado pelo driver)
    os.environ.setdefault('PYO_DEBUG_PACKETS', '1')
    os.environ.setdefault('PYO_DEBUG_MESSAGES', '1')
    os.environ.setdefault('PYO_DEBUG', '1')
    print('[PY-DEBUG] Debug flags:', {k: v for k, v in os.environ.items() if k.startswith('PYO_')})

    print(f'Connecting as {user}@{dsn} using local python-oracledb checkout...')
    with oracledb.connect(user=user, password=password, dsn=dsn) as conn:
        print('[PY-DEBUG] Connected. mode=thin?', conn.thin)
        with conn.cursor() as cursor:
            cursor.execute('SELECT 1 FROM dual')
            result = cursor.fetchone()
            print('Query result:', result)


if __name__ == '__main__':
    trace_file = os.getenv('PYTHON_AUTH_TRACE_FILE')
    if trace_file:
        os.environ.setdefault('PYO_DEBUG_PACKETS', '1')
        with open(trace_file, 'w', encoding='ascii', buffering=1) as fh:
            fh.write(f'# PYTHON_AUTH_TRACE_FILE={trace_file}\n')
            fh.write(f"# Debug flags: { {k: v for k, v in os.environ.items() if k.startswith('PYO_')} }\n\n")
            with contextlib.redirect_stdout(fh):
                main()
            # Tentativa de imprimir env úteis para depuração (salt/counters devem
            # aparecer nos logs do driver se suportado pelas flags acima).
            print('Ambiente de debug Python gravado em', trace_file)
        print(f'Pacotes Python registrados em {trace_file}')
    else:
        main()
