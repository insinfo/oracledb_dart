import 'connection.dart';
import 'exceptions.dart';
import 'placeholders.dart';
import 'thin/cursor_impl.dart';
import 'thin/messages/base.dart';
import 'thin/messages/execute.dart';
import 'thin/constants.dart';
import 'thin/types.dart';
import 'thin/variable.dart';

enum PipelineOpType {
  callFunc,
  callProc,
  commit,
  execute,
  executeMany,
  fetchAll,
  fetchMany,
  fetchOne,
}

/// An operation added to an [OraclePipeline].
class PipelineOp {
  PipelineOp._(this.type,
      {this.statement,
      this.parameters,
      this.name,
      this.returnType,
      this.numRows = 0,
      this.arraySize = 1000});

  final PipelineOpType type;
  final String? statement;
  final Object? parameters;
  final String? name;
  final DbType? returnType;
  final int numRows;
  final int arraySize;
}

/// The result of an operation of a pipeline.
class PipelineOpResult {
  PipelineOpResult(this.operation);

  final PipelineOp operation;

  /// Rows fetched (fetch operations).
  List<List<Object?>>? rows;

  /// Column metadata (fetch operations).
  List<ColumnMetadata>? columns;

  /// Return value (callFunc operations).
  Object? returnValue;

  OracleException? warning;

  /// The error raised by the operation, when the pipeline was run with
  /// `continueOnError`.
  Object? error;
}

/// A list of operations sent to the database in a single round trip with
/// [OracleConnection.runPipeline]. Pipelining requires Oracle Database 23ai;
/// with older databases the operations are executed one after the other.
class OraclePipeline {
  final List<PipelineOp> operations = [];

  PipelineOp _add(PipelineOp op) {
    operations.add(op);
    return op;
  }

  PipelineOp addExecute(String statement, [Object? parameters]) =>
      _add(PipelineOp._(PipelineOpType.execute,
          statement: statement, parameters: parameters));

  PipelineOp addExecuteMany(String statement, List<Object?> rows) =>
      _add(PipelineOp._(PipelineOpType.executeMany,
          statement: statement, parameters: rows));

  PipelineOp addFetchOne(String statement, [Object? parameters]) =>
      _add(PipelineOp._(PipelineOpType.fetchOne,
          statement: statement, parameters: parameters));

  PipelineOp addFetchMany(String statement,
          {Object? parameters, int numRows = 100}) =>
      _add(PipelineOp._(PipelineOpType.fetchMany,
          statement: statement, parameters: parameters, numRows: numRows));

  PipelineOp addFetchAll(String statement,
          {Object? parameters, int arraySize = 1000}) =>
      _add(PipelineOp._(PipelineOpType.fetchAll,
          statement: statement, parameters: parameters, arraySize: arraySize));

  PipelineOp addCallFunc(String name, DbType returnType,
          [List<Object?> parameters = const []]) =>
      _add(PipelineOp._(PipelineOpType.callFunc,
          name: name, returnType: returnType, parameters: parameters));

  PipelineOp addCallProc(String name, [List<Object?> parameters = const []]) =>
      _add(PipelineOp._(PipelineOpType.callProc,
          name: name, parameters: parameters));

  PipelineOp addCommit() => _add(PipelineOp._(PipelineOpType.commit));
}

String _callSql(String name, int numParams, {bool function = false}) {
  final offset = function ? 2 : 1;
  final placeholders =
      [for (var i = 0; i < numParams; i++) ':${i + offset}'].join(', ');
  return function
      ? 'begin :1 := $name($placeholders); end;'
      : 'begin $name($placeholders); end;';
}

/// Runs the pipeline on [conn] (used by [OracleConnection.runPipeline]).
Future<List<PipelineOpResult>> runPipeline(OracleConnection conn,
    OraclePipeline pipeline, bool continueOnError) async {
  final impl = conn.impl;
  final results = [for (final op in pipeline.operations) PipelineOpResult(op)];
  if (!impl.protocol.caps.supportsPipelining) {
    await _runSequentially(conn, results, continueOnError);
    return results;
  }

  // create a message for each operation
  final messages = <Message>[];
  final byMessage = <Message, PipelineOpResult>{};
  final cursors = <Message, ThinCursorImpl>{};
  final returnVars = <Message, BindVar>{};
  var tokenNum = 1;
  for (final result in results) {
    final op = result.operation;
    try {
      Message message;
      if (op.type == PipelineOpType.commit) {
        message = SimpleMessage(impl, TNS_FUNC_COMMIT);
      } else {
        final cursor = ThinCursorImpl(impl);
        var sql = op.statement;
        Object? params = op.parameters;
        BindVar? returnVar;
        if (op.type == PipelineOpType.callFunc) {
          returnVar = BindVar.forType(op.returnType!);
          final args = op.parameters as List<Object?>;
          sql = _callSql(op.name!, args.length, function: true);
          params = [returnVar, ...args];
        } else if (op.type == PipelineOpType.callProc) {
          sql = _callSql(op.name!, (op.parameters as List).length);
        } else {
          sql = prepareSql(sql!, conn.placeholderIdentifier);
        }
        cursor.prepare(sql);
        final execute = ExecuteMessage(cursor);
        switch (op.type) {
          case PipelineOpType.executeMany:
            final rows = op.parameters as List<Object?>;
            cursor.bindMany(rows);
            execute.numExecs =
                cursor.statement!.requiresSingleExecute ? 1 : rows.length;
          case PipelineOpType.fetchOne:
            cursor.bind(params);
            cursor
              ..prefetchRows = 1
              ..arraySize = 1;
          case PipelineOpType.fetchMany:
            cursor.bind(params);
            cursor
              ..prefetchRows = op.numRows
              ..arraySize = op.numRows;
          case PipelineOpType.fetchAll:
            cursor.bind(params);
            cursor
              ..prefetchRows = op.arraySize
              ..arraySize = op.arraySize;
          default:
            cursor.bind(params);
        }
        if (returnVar != null) returnVars[execute] = returnVar;
        cursors[execute] = cursor;
        message = execute;
      }
      message
        ..inPipeline = true
        ..tokenNum = tokenNum++;
      messages.add(message);
      byMessage[message] = result;
    } catch (e) {
      if (!continueOnError) rethrow;
      result.error = e;
    }
  }
  if (messages.isEmpty) return results;

  await impl.protocol.runPipeline(messages, EndPipelineMessage(impl),
      continueOnError, (message, error) => byMessage[message]!.error = error);

  // complete the operations (LOB defines, remaining rows, ...)
  for (final message in messages) {
    final result = byMessage[message]!;
    final cursor = cursors[message];
    if (result.error != null || cursor == null) continue;
    try {
      final execute = message as ExecuteMessage;
      result.warning = execute.warning;
      execute.inPipeline = false;
      execute.tokenNum = 0;
      if (execute.resend) await impl.protocol.resendMessage(execute);
      final op = result.operation;
      switch (op.type) {
        case PipelineOpType.callFunc:
          result.returnValue = returnVars[message]!.values[0];
        case PipelineOpType.fetchOne:
        case PipelineOpType.fetchMany:
          result.rows = cursor.takeBufferedRows();
        case PipelineOpType.fetchAll:
          result.rows = await cursor.fetchAll();
        case PipelineOpType.executeMany:
          final rows = op.parameters as List<Object?>;
          if (execute.numExecs < rows.length) {
            // a PL/SQL block executed for the first time runs once to
            // determine the bind directions; the remaining rows follow
            final rest = ExecuteMessage(cursor)
              ..numExecs = rows.length - 1
              ..offset = 1;
            await impl.protocol.processSingleMessage(rest);
          }
        default:
          break;
      }
      result.columns = cursor.fetchMetadata;
      cursor.close();
    } catch (e) {
      if (!continueOnError) rethrow;
      result.error = e;
    }
  }
  return results;
}

Future<void> _runSequentially(OracleConnection conn,
    List<PipelineOpResult> results, bool continueOnError) async {
  for (final result in results) {
    final op = result.operation;
    try {
      if (op.type == PipelineOpType.commit) {
        await conn.commit();
        continue;
      }
      final cursor = conn.cursor();
      switch (op.type) {
        case PipelineOpType.callFunc:
          result.returnValue = await cursor.callFunc(
              op.name!, op.returnType!, op.parameters as List<Object?>);
        case PipelineOpType.callProc:
          await cursor.callProc(op.name!, op.parameters as List<Object?>);
        case PipelineOpType.execute:
          await cursor.execute(op.statement!, op.parameters);
        case PipelineOpType.executeMany:
          await cursor.executeMany(
              op.statement!, op.parameters as List<Object?>);
        case PipelineOpType.fetchAll:
          cursor.arraySize = op.arraySize;
          await cursor.execute(op.statement!, op.parameters);
          result.rows = await cursor.fetchAll();
        case PipelineOpType.fetchMany:
          await cursor.execute(op.statement!, op.parameters);
          result.rows = await cursor.fetchMany(op.numRows);
        case PipelineOpType.fetchOne:
          await cursor.execute(op.statement!, op.parameters);
          result.rows = await cursor.fetchMany(1);
        case PipelineOpType.commit:
          break;
      }
      result.warning = cursor.warning;
      result.columns = cursor.description;
      cursor.close();
    } catch (e) {
      if (!continueOnError) rethrow;
      result.error = e;
    }
  }
}
