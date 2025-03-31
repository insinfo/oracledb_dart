Princípios Gerais:

Priorizar a API Pública: Comece definindo a interface que os usuários Dart consumirão.

Priorizar o Modo Thin: O modo Thin (implementação pura em Python/Cython sem dependência da biblioteca C do Oracle Client) é muito mais viável de portar do que o modo Thick (que depende fortemente de C interop via ODPI-C). Concentre-se em fazer o modo Thin funcionar primeiro. O modo Thick exigiria um esforço massivo de FFI (Foreign Function Interface) em Dart, que está além da capacidade de tradução direta de um LLM.

Abstrair Implementações Internas: Não tente fazer o LLM traduzir diretamente os arquivos .pyx de baixo nível (especialmente thick_impl.pyx e grande parte de base_impl.pyx). Use-os como referência para entender a lógica e o protocolo, mas a implementação Dart provavelmente precisará ser reescrita usando bibliotecas e padrões Dart (Sockets, Streams, async/await, criptografia Dart).

Incremental e Iterativo: Construa a base primeiro e depois adicione funcionalidades. Teste continuamente.

Foco nas Assinaturas Primeiro: Use o LLM para obter as assinaturas de métodos e propriedades das classes públicas em Dart, depois preencha a implementação.

LLM como Assistente: O LLM acelera a tradução de código Python puro e a compreensão da lógica, mas não substituirá a necessidade de um desenvolvedor Dart entender o código original e escrever/adaptar a implementação Dart idiomática.

Plano Detalhado de Portabilidade (Ordem de Arquivos para o LLM):

Fase 0: Fundação e Estrutura do Projeto Dart

Configuração do Projeto Dart: Crie a estrutura de pastas do projeto Dart (lib, test, pubspec.yaml, etc.).

Constantes e Enumerações:

Arquivo(s) para LLM: src/oracledb/constants.py, src/oracledb/enums.py

Instrução para LLM: "Traduza estas constantes e enumerações Python para constantes const e enums idiomáticos em Dart."

Revisão Humana: Verifique os tipos e nomes em Dart.

Exceções:

Arquivo(s) para LLM: src/oracledb/exceptions.py, src/oracledb/errors.py (para mapeamento de mensagens/códigos)

Instrução para LLM: "Defina uma hierarquia de exceções em Dart baseada nestas classes Python (Warning, Error, DatabaseError, etc.). Extraia os códigos de erro e mensagens de errors.py para referência, mas a estrutura de exceção Dart será diferente."

Revisão Humana: Implemente a hierarquia de exceções Dart, possivelmente com uma classe base OracleException e subclasses específicas. O mapeamento de erros do errors.py precisará ser adaptado.

Tipos de Dados Básicos:

Arquivo(s) para LLM: src/oracledb/base_impl.pyx (apenas as definições de DbType e ApiType)

Instrução para LLM: "Com base nas definições de DbType e ApiType neste arquivo Cython, defina classes ou enums Dart correspondentes para representar os tipos de dados do Oracle e os tipos da API DB."

Revisão Humana: Defina OracleDbType (enum ou classe) e talvez OracleApiType em Dart.

Fase 1: Definição da API Pública Principal (Interfaces/Abstract Classes)

O objetivo aqui é ter as assinaturas em Dart, não a implementação.

Conexão:

Arquivo(s) para LLM: src/oracledb/connection.py (Classes BaseConnection, Connection, AsyncConnection)

Instrução para LLM: "Traduza as assinaturas públicas (métodos e propriedades) das classes BaseConnection, Connection e AsyncConnection para classes abstratas Dart (BaseOracleConnection, OracleConnection, OracleAsyncConnection). Converta métodos bloqueantes para Futures em Dart. Ignore implementações internas, construtores e métodos privados/protegidos (prefixo _). Mapeie tipos Python (como bytes para Uint8List, Callable para Function, datetime para DateTime, Xid para um Record ou classe Dart simples)."

Cursor:

Arquivo(s) para LLM: src/oracledb/cursor.py (Classes BaseCursor, Cursor, AsyncCursor)

Instrução para LLM: "Traduza as assinaturas públicas das classes BaseCursor, Cursor e AsyncCursor para classes abstratas Dart (BaseOracleCursor, OracleCursor, OracleAsyncCursor). Converta métodos bloqueantes para Futures. Considere mapear a iteração (__next__, __anext__) para Streams em Dart (mas foque na assinatura dos métodos fetch primeiro). Ignore implementações internas e métodos privados/protegidos."

Pool de Conexões:

Arquivo(s) para LLM: src/oracledb/pool.py (Classes BaseConnectionPool, ConnectionPool, AsyncConnectionPool)

Instrução para LLM: "Traduza as assinaturas públicas das classes de Pool para classes abstratas Dart (BaseOracleConnectionPool, OracleConnectionPool, OracleAsyncConnectionPool). Converta métodos bloqueantes para Futures. Ignore implementações internas e métodos privados/protegidos."

Parâmetros de Configuração:

Arquivo(s) para LLM: src/oracledb/connect_params.py, src/oracledb/pool_params.py

Instrução para LLM: "Traduza as classes ConnectParams e PoolParams para classes de dados Dart (OracleConnectParams, OraclePoolParams) ou classes usando o padrão Builder. Foque nas propriedades públicas."

Revisão Humana: Decida entre data classes simples ou Builder pattern para Dart.

LOB (Large Objects):

Arquivo(s) para LLM: src/oracledb/lob.py (Classes BaseLOB, LOB, AsyncLOB)

Instrução para LLM: "Traduza as assinaturas públicas das classes LOB para classes abstratas Dart (BaseOracleLob, OracleLob, OracleAsyncLob). Converta métodos bloqueantes para Futures."

Variáveis (Var):

Arquivo(s) para LLM: src/oracledb/var.py (Classe Var)

Instrução para LLM: "Traduza as assinaturas públicas da classe Var para uma classe abstrata Dart (OracleVar)."

Informações de Fetch:

Arquivo(s) para LLM: src/oracledb/fetch_info.py (Classe FetchInfo)

Instrução para LLM: "Traduza as propriedades públicas da classe FetchInfo para uma classe Dart (FetchInfo)."

Fase 2: Implementação do Núcleo do Modo Thin (Maior Esforço Manual)

Esta fase é crítica e exigirá mais do que tradução direta. O LLM pode ajudar a entender a lógica do protocolo TNS nos arquivos .pyx, mas a implementação Dart será substancialmente diferente.

Lógica do Protocolo TNS (Thin):

Arquivo(s) para LLM (Referência/Análise): src/oracledb/thin_impl.pyx, src/oracledb/impl/thin/protocol.pyx, src/oracledb/impl/thin/transport.pyx, src/oracledb/impl/thin/packet.pyx, src/oracledb/impl/thin/capabilities.pyx, src/oracledb/impl/thin/crypto.pyx, arquivos em src/oracledb/impl/thin/messages/

Instrução para LLM (Exemplo): "Analise a lógica nestes arquivos relacionada ao protocolo Oracle Net Services (TNS) usado no modo Thin. Descreva os passos para: 1. Estabelecer uma conexão (negociação de versão, capabilities, autenticação O5Logon). 2. Enviar uma consulta SQL simples. 3. Receber e decodificar a resposta (pacotes de dados, tipos de dados). 4. Lidar com autenticação (O5Logon, senhas). 5. Lidar com criptografia (se aplicável). Gere snippets conceituais de código Dart para essas etapas, focando na lógica do protocolo, não na sintaxe Cython."

Tarefa Manual: Implementar a stack do protocolo TNS em Dart. Isso envolve:

Sockets e comunicação de rede assíncrona (dart:io, dart:async).

Empacotamento e desempacotamento de pacotes TNS.

Implementação dos diferentes tipos de mensagens TNS (Auth, Execute, Fetch, etc.).

Lógica de autenticação (provavelmente O5Logon ou mais recente).

Criptografia (usando pacotes Dart como cryptography ou pointycastle se Network Encryption for suportada).

Conversão entre tipos de dados Oracle (TTC) e tipos Dart.

Implementação Concreta (Thin):

Tarefa Manual: Crie classes concretas em Dart (ThinOracleConnection, ThinOracleCursor, ThinOraclePool, etc.) que implementem as interfaces/classes abstratas da Fase 1, utilizando a camada de protocolo TNS construída acima. O LLM pode ajudar a traduzir a lógica de alto nível dos métodos públicos (ex: connection.commit() envia uma mensagem TNS de commit), mas não a interação detalhada com a camada de protocolo.

Fase 3: Componentes de Suporte e Utilitários

Utilitários e Padrões:

Arquivo(s) para LLM: src/oracledb/utils.py, src/oracledb/defaults.py, src/oracledb/dsn.py, src/oracledb/driver_mode.py (para lógica, não estado global).

Instrução para LLM: "Traduza estas funções utilitárias e configurações padrão para Dart. Adapte a lógica de registro de hooks (se aplicável) para um mecanismo Dart (talvez usando injeção de dependência ou um registro simples)."

Revisão Humana: Integre os utilitários, implemente a classe OracleDefaults, adapte a lógica makedsn (se necessário). O gerenciamento de modo (Thin/Thick) provavelmente será mais simples ou diferente em Dart.

Fase 4: Funcionalidades Avançadas (Thin)

DbObject (Thin):

Arquivo(s) para LLM: src/oracledb/dbobject.py (API pública), src/oracledb/impl/thin/dbobject.pyx, src/oracledb/impl/thin/dbobject_cache.pyx (Lógica de empacotamento/desempacotamento e cache Thin).

Instrução para LLM: "Com base na interface OracleDbObject/OracleDbObjectType/OracleDbObjectAttr definida anteriormente, traduza a lógica de empacotamento/desempacotamento (pickling) e cache encontrada nos arquivos dbobject.pyx da implementação Thin para Dart. Gere a implementação das classes concretas."

Tarefa Manual: Implementar o empacotamento/desempacotamento (TDS/pickler) em Dart e a lógica de cache.

AQ (Advanced Queuing - Thin):

Arquivo(s) para LLM: src/oracledb/aq.py (API pública), src/oracledb/impl/thin/queue.pyx, mensagens AQ em src/oracledb/impl/thin/messages/.

Instrução para LLM: "Implemente as classes concretas Dart para AQ (ThinOracleQueue, etc.) baseadas nas interfaces da Fase 1, traduzindo a lógica de envio/recebimento de mensagens AQ TNS encontrada nos arquivos Thin."

Tarefa Manual: Refinar a implementação e garantir a correta serialização/desserialização das propriedades da mensagem.

SODA (Simple Oracle Document Access - Thin):

Arquivo(s) para LLM: src/oracledb/soda.py (API pública), src/oracledb/impl/thin/soda.pyx (Lógica Thin).

Instrução para LLM: "Implemente as classes concretas Dart para SODA (ThinOracleSodaDatabase, etc.) baseadas nas interfaces da Fase 1, traduzindo a lógica das operações SODA TNS encontrada nos arquivos Thin."

Tarefa Manual: Refinar implementação, especialmente a manipulação de documentos JSON/OSON.

Pipeline (Thin):

Arquivo(s) para LLM: src/oracledb/pipeline.py (API pública), lógica de pipeline em src/oracledb/impl/thin/connection.pyx e mensagens relacionadas.

Instrução para LLM: "Implemente as classes concretas Dart para Pipeline (ThinOraclePipeline, etc.) baseadas nas interfaces da Fase 1, traduzindo a lógica de envio/recebimento de operações em pipeline TNS encontrada nos arquivos Thin."

Tarefa Manual: Gerenciar o estado do pipeline e o processamento de resultados/erros.

Sparse Vector (Thin):

Arquivo(s) para LLM: src/oracledb/sparse_vector.py (API pública), lógica de vetor em src/oracledb/impl/thin/protocol.pyx (se houver manipulação específica) e mensagens relacionadas.

Instrução para LLM: "Implemente a classe OracleSparseVector e a lógica de serialização/desserialização para o tipo VECTOR TNS."

Tarefa Manual: Garantir a correta codificação/decodificação do formato VECTOR.

Fase 5: Intercâmbio de Dados (DataFrame - Opcional)

DataFrame Interchange:

Arquivo(s) para LLM: src/oracledb/interchange/* (principalmente os .py)

Instrução para LLM: "Traduza as classes Python que implementam o protocolo DataFrame Interchange (OracleDataFrame, OracleColumn, OracleColumnBuffer) para Dart, aderindo às interfaces definidas no protocolo (que precisariam ser definidas em Dart primeiro)."

Tarefa Manual: Esta parte depende fortemente da existência de bibliotecas Arrow/DataFrame em Dart. A ponte nanoarrow_bridge.pyx (C interop) precisaria de uma implementação Dart FFI se Arrow C for usado, ou uma adaptação para uma biblioteca Arrow Dart.

Fase 6: Plugins (Opcional)

Plugins (Azure/OCI):

Arquivo(s) para LLM: src/oracledb/plugins/*

Instrução para LLM: "Traduza a lógica destes plugins. Substitua as chamadas aos SDKs Python do Azure/OCI pelas chamadas aos SDKs Dart correspondentes. Adapte o mecanismo de registro de hooks."

Tarefa Manual: Requer os SDKs Dart para Azure e OCI. O registro de hooks precisará ser reimplementado em Dart.

Fase 7: Testes e Refinamento

Testes Unitários e de Integração: Escreva testes abrangentes em Dart para validar a funcionalidade portada em relação a um banco de dados Oracle real.

Refatoração: Refatore o código Dart para melhorar a idiomaticidade, desempenho e manutenibilidade.

Considerações Adicionais:

Cython: Onde o Cython é usado para otimização de performance em lógica Python pura (sem chamadas C diretas), o LLM pode traduzir a lógica Python equivalente, mas a otimização precisará ser refeita em Dart, se necessário. Onde o Cython faz interop C (especialmente no modo Thick), a tradução LLM será inadequada.

FFI (Thick Mode): Portar o modo Thick exigiria criar manualmente bindings Dart FFI para a biblioteca ODPI-C (ou diretamente OCI). Este é um trabalho complexo e propenso a erros.

Gerenciamento de Memória: Dart usa garbage collection. O código Cython pode ter gerenciamento manual de memória ou contagem de referências que não se traduzem diretamente.

Bibliotecas Externas: A funcionalidade de bibliotecas Python como cryptography, msal, oci precisará ser substituída por pacotes Dart equivalentes.

Este plano prioriza a obtenção de um driver funcional no modo Thin, que é o caminho mais realista usando um LLM como assistente.