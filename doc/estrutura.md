sugestão de estrutura de pastas e arquivos para o seu projeto Dart, seguindo o plano de portabilidade focado no modo Thin e priorizando a API pública. Esta estrutura adota as convenções do Dart e separa claramente a API pública da implementação interna.

oracle_db/
├── lib/
│   ├── oracle_db.dart            # Ponto de entrada principal, exporta a API pública
│   │
│   ├── connection.dart           # Interface/Classe Abstrata OracleConnection, AsyncOracleConnection
│   ├── cursor.dart               # Interface/Classe Abstrata OracleCursor, AsyncOracleCursor
│   ├── pool.dart                 # Interface/Classe Abstrata OracleConnectionPool, AsyncOracleConnectionPool, getPool
│   ├── lob.dart                  # Interface/Classe Abstrata OracleLob, AsyncOracleLob
│   ├── db_object.dart            # Interface/Classe Abstrata OracleDbObject, OracleDbObjectType, OracleDbObjectAttr
│   ├── soda.dart                 # Interfaces/Classes Abstratas para SODA (Database, Collection, Document, etc.)
│   ├── aq.dart                   # Interfaces/Classes Abstratas para AQ (Queue, MessageProperties, Options)
│   ├── pipeline.dart             # Interface/Classe Abstrata OraclePipeline, OraclePipelineOp, OraclePipelineResult
│   ├── var.dart                  # Interface/Classe Abstrata OracleVar
│   ├── connect_params.dart       # Classe OracleConnectParams (ou Builder)
│   ├── pool_params.dart          # Classe OraclePoolParams (ou Builder)
│   ├── fetch_info.dart           # Classe FetchInfo
│   ├── sparse_vector.dart        # Classe OracleSparseVector
│   ├── subscription.dart         # Interface/Classe Abstrata OracleSubscription, Message*, etc.
│   ├── dataframe.dart            # Interfaces DataFrame Interchange (se implementado)
│   │
│   ├── constants.dart            # Constantes públicas (AQ, Shutdown, Subs, etc.)
│   ├── enums.dart                # Enums públicos (AuthMode, PoolGetMode, Purity, etc.)
│   ├── exceptions.dart           # Hierarquia de exceções públicas (OracleException, DatabaseException, etc.)
│   ├── types.dart                # Definições de tipos públicos (OracleDbType, TpcXid, etc.)
│   ├── defaults.dart             # Classe OracleDefaults ou acesso aos padrões
│   ├── dsn.dart                  # Função utilitária makeConnectString (equivalente a makedsn)
│   ├── utils.dart                # Funções utilitárias públicas (initOracleClient, clientVersion, register*, etc.)
│   │
│   └── src/                      # Implementação interna (não importada diretamente pelo usuário)
│       ├── base/                 # Lógica interna potencialmente compartilhada
│       │   ├── type_converter.dart # Conversores de tipo Oracle <-> Dart
│       │   ├── utils.dart          # Utilitários internos
│       │   └── connect_string_parser.dart # Lógica de parsing de connect string
│       │
│       ├── thin/                 # Implementação do Modo Thin (Pure Dart)
│       │   ├── protocol/         # Lógica do protocolo TNS
│       │   │   ├── constants.dart
│       │   │   ├── capabilities.dart
│       │   │   ├── transport.dart    # Sockets, SSL/TLS
│       │   │   ├── packet.dart       # Leitura/escrita de pacotes TNS
│       │   │   ├── protocol.dart     # Máquina de estado/handler do protocolo TNS
│       │   │   └── messages/         # Classes para cada tipo de mensagem TNS
│       │   │       ├── base.dart
│       │   │       ├── connect.dart
│       │   │       ├── auth.dart
│       │   │       ├── execute.dart
│       │   │       ├── fetch.dart
│       │   │       ├── commit.dart
│       │   │       ├── rollback.dart
│       │   │       ├── lob_op.dart
│       │   │       ├── aq_*.dart
│       │   │       ├── tpc_*.dart
│       │   │       ├── end_pipeline.dart
│       │   │       └── ...           # Outras mensagens
│       │   │
│       │   ├── crypto/           # Lógica de criptografia (O5Logon, etc.)
│       │   │   └── utils.dart      # (ou arquivos específicos por algoritmo)
│       │   │
│       │   ├── connection_impl.dart # Implementação ThinOracleConnection / Async
│       │   ├── cursor_impl.dart     # Implementação ThinOracleCursor / Async
│       │   ├── pool_impl.dart       # Implementação ThinOraclePool / Async
│       │   ├── lob_impl.dart        # Implementação ThinOracleLob / Async
│       │   ├── var_impl.dart        # Implementação interna para OracleVar
│       │   ├── statement_cache.dart # Lógica de cache de statements
│       │   ├── db_object_impl.dart  # Implementação Thin para DbObject (parsing TDS, etc.)
│       │   ├── db_object_cache.dart # Cache de tipos de DbObject para Thin
│       │   ├── aq_impl.dart         # Implementação Thin para AQ
│       │   ├── soda_impl.dart       # Implementação Thin para SODA
│       │   ├── pipeline_impl.dart   # Implementação Thin para Pipeline
│       │   ├── sparse_vector_impl.dart # Implementação Thin para SparseVector
│       │   └── subscription_impl.dart # Implementação Thin para Subscription
│       │
│       ├── thick/                # Implementação do Modo Thick (FFI - Placeholder)
│       │   ├── ffi/                # Bindings FFI para ODPI-C
│       │   │   └── odpi_bindings.dart
│       │   │
│       │   ├── connection_impl.dart
│       │   ├── cursor_impl.dart
│       │   └── ...               # Outras implementações Thick
│       │
│       ├── interchange/          # Implementação do DataFrame Interchange (se aplicável)
│       │   ├── dataframe_impl.dart
│       │   ├── column_impl.dart
│       │   └── buffer_impl.dart
│       │
│       └── plugins/              # Implementação de Plugins (se aplicável)
│           ├── azure/
│           └── oci/
│
├── test/                       # Testes unitários e de integração
│   ├── connection_test.dart
│   ├── cursor_test.dart
│   ├── pool_test.dart
│   └── ...
│
├── example/                    # Exemplos de uso
│   ├── connect_example.dart
│   ├── pool_example.dart
│   └── ...
│
├── pubspec.yaml                # Definições do pacote, dependências
├── README.md
├── CHANGELOG.md
└── LICENSE
Use code with caution.
Ordem de Processamento com LLM (conforme o plano):

Fase 0: Dê ao LLM constants.py e enums.py para gerar lib/constants.dart e lib/enums.dart. Dê exceptions.py para gerar lib/exceptions.dart. Dê as definições de DbType/ApiType de base_impl.pyx para gerar lib/types.dart.

Fase 1 (API Pública): Processe os arquivos .py públicos um por um (ou em pequenos grupos relacionados) para gerar as classes abstratas/interfaces correspondentes em lib/:

connection.py -> lib/connection.dart (assinaturas)

cursor.py -> lib/cursor.dart (assinaturas)

pool.py -> lib/pool.dart (assinaturas)

connect_params.py, pool_params.py -> lib/connect_params.dart, lib/pool_params.dart (propriedades)

lob.py -> lib/lob.dart (assinaturas)

var.py -> lib/var.dart (assinaturas)

fetch_info.py -> lib/fetch_info.dart (propriedades)

dbobject.py -> lib/db_object.dart (assinaturas)

aq.py -> lib/aq.dart (assinaturas)

soda.py -> lib/soda.dart (assinaturas)

pipeline.py -> lib/pipeline.dart (assinaturas)

sparse_vector.py -> lib/sparse_vector.dart (propriedades)

subscription.py -> lib/subscription.dart (assinaturas)

Fase 2 (Núcleo Thin - Análise/Geração Conceitual): Use os arquivos .pyx do modo Thin (thin_impl.pyx, impl/thin/*) como referência. Peça ao LLM para explicar a lógica TNS e gerar snippets conceituais para a implementação em Dart (dentro de lib/src/thin/protocol/ e lib/src/thin/crypto/). A maior parte desta fase será codificação manual em Dart.

Fase 2 (Implementação Concreta): Após a camada de protocolo TNS estar funcional, comece a implementar as classes concretas em lib/src/thin/ (ex: connection_impl.dart, cursor_impl.dart). Use o LLM para ajudar a traduzir a lógica dentro dos métodos públicos das classes Python/Cython correspondentes, adaptando-a para usar a camada de protocolo Dart.

Fase 3 (Utilitários): Dê ao LLM utils.py, defaults.py, dsn.py para gerar lib/utils.dart, lib/defaults.dart, lib/dsn.dart.

Fase 4 (Avançadas Thin): Aborde as funcionalidades como DbObject, AQ, SODA, Pipeline, SparseVector. Use os arquivos .py e os .pyx da implementação Thin como referência para o LLM ajudar a implementar as classes concretas em lib/src/thin/.

Fase 5 (DataFrame - Opcional): Processe src/oracledb/interchange/*.

Fase 6 (Plugins - Opcional): Processe src/oracledb/plugins/*.

Lembre-se: O LLM é um co-piloto. Você precisará guiar, revisar, refatorar e, principalmente na Fase 2, escrever uma quantidade significativa de código Dart idiomático. Boa sorte!