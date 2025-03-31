import 'dart:io';
import 'dart:convert';

class MergeConfig {
  final List<String> directories;
  final List<String> extensions;
  final String outputFileName;
  final String importPattern;

  const MergeConfig({
    required this.directories,
    required this.extensions,
    required this.outputFileName,
    required this.importPattern,
  });
}

List<String> collectImports(String content, String pattern) {
  final importLines = <String>[];
  final importRegex = RegExp(pattern);
  
  for (final line in LineSplitter.split(content)) {
    if (importRegex.hasMatch(line)) {
      importLines.add(line);
    }
  }
  return importLines;
}

Future<void> mergeFiles(MergeConfig config) async {
  final imports = <String>{};
  final mergedContent = <String>[];

  for (final directory in config.directories) {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      print('Directory not found: $directory');
      continue;
    }

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && 
          config.extensions.any((ext) => entity.path.endsWith(ext))) {
        final content = await entity.readAsString();
        
        imports.addAll(collectImports(content, config.importPattern));
        
        mergedContent.addAll([
          '\n# ${'=' * 40}',
          '# Source file: ${entity.path}',
          '# ${'=' * 40}\n',
          content
        ]);
      }
    }
  }

  final outputPath = '${Directory(config.directories.first).parent.path}/${config.outputFileName}';
  final outputFile = File(outputPath);
  
  final output = [
    '# All imports',
    ...imports.toList()..sort(),
    '',
    ...mergedContent
  ].join('\n');

  await outputFile.writeAsString(output);
}

void main() async {
  // Configuração para arquivos Python
  final pythonConfig = MergeConfig(
    directories: [
      r'C:\MyProjectsDart\oracledb_dart\python-oracledb\src\oracledb',
      // Adicione mais diretórios aqui se necessário
    ],
    extensions: ['.py','pyx'],
    outputFileName: 'merged_oracledb.py',
    importPattern: r'^(import|from)\s+',
  );

  // Exemplo de configuração para Dart (comentado)
  // final dartConfig = MergeConfig(
  //   directories: [r'C:\MyProjectsDart\oracledb_dart\lib'],
  //   extensions: ['.dart'],
  //   outputFileName: 'merged_dart.dart',
  //   importPattern: r'^import\s+',
  // );

  await mergeFiles(pythonConfig);
  print('Files merged successfully. Check "${pythonConfig.outputFileName}"');
}
