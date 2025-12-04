import 'dart:io';

void main() async {
  // Diretório de origem
  final sourceDir = Directory(r'C:\MyDartProjects\oracledb_dart\lib');

  // Arquivo de saída
  final outputFile =
      File(r'C:\MyDartProjects\oracledb_dart\scripts\merged_code.dart.txt');

  print('Iniciando mesclagem de arquivos Dart...');
  print('Diretório: ${sourceDir.path}');

  // Verifica se o diretório existe
  if (!await sourceDir.exists()) {
    print('Erro: Diretório não encontrado!');
    exit(1);
  }

  // Lista todos os arquivos .dart no diretório
  final dartFiles = <File>[];
  await for (final entity in sourceDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      // Ignora o próprio arquivo de saída se ele já existir
      if (entity.path != outputFile.path) {
        dartFiles.add(entity);
      }
    }
  }

  if (dartFiles.isEmpty) {
    print('Nenhum arquivo .dart encontrado no diretório.');
    exit(0);
  }

  print('Encontrados ${dartFiles.length} arquivo(s) .dart');

  // Cria o conteúdo mesclado
  final buffer = StringBuffer();
  buffer.writeln('// Arquivo mesclado automaticamente');
  buffer.writeln('// Data: ${DateTime.now()}');
  buffer.writeln('// Total de arquivos: ${dartFiles.length}');
  buffer.writeln();

  for (final file in dartFiles) {
    final relativePath = file.path.replaceAll(sourceDir.path, '');
    print('Processando: $relativePath');

    buffer.writeln('// Arquivo: $relativePath');
    buffer.writeln();

    final content = await file.readAsString();
    buffer.writeln(content);
    buffer.writeln();
    buffer.writeln();
  }

  // Escreve o arquivo de saída
  await outputFile.writeAsString(buffer.toString());

  print('\nMesclagem concluída!');
  print('Arquivo de saída: ${outputFile.path}');
  print('Tamanho: ${(await outputFile.length() / 1024).toStringAsFixed(2)} KB');
}
