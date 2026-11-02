import 'package:oracledb_dart/src/placeholders.dart';
import 'package:test/test.dart';

void main() {
  test('question marks become positional placeholders', () {
    expect(convertQuestionMarks('select * from t where a = ? and b = ?'),
        'select * from t where a = :1 and b = :2');
    expect(convertQuestionMarks('insert into t values (?,?,?)'),
        'insert into t values (:1,:2,:3)');
    expect(convertQuestionMarks('select 1 from dual'), 'select 1 from dual');
  });

  test('question marks in literals, identifiers and comments are kept', () {
    expect(convertQuestionMarks("select '?', 'it''s ?', ? from dual"),
        "select '?', 'it''s ?', :1 from dual");
    expect(convertQuestionMarks('select "a?b", ? from dual'),
        'select "a?b", :1 from dual');
    expect(convertQuestionMarks("select q'[?]', q'{x?}', ? from dual"),
        "select q'[?]', q'{x?}', :1 from dual");
    expect(convertQuestionMarks('select ? -- why?\nfrom dual where x = ?'),
        'select :1 -- why?\nfrom dual where x = :2');
    expect(convertQuestionMarks('select /* ? */ ? from dual'),
        'select /* ? */ :1 from dual');
  });

  test('colon style leaves the statement unchanged', () {
    expect(prepareSql('select ? from dual', PlaceholderIdentifier.colon),
        'select ? from dual');
  });
}
