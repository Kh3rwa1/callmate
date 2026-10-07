import 'dart:typed_data';

import 'package:callpilot/core/utils/file_pick.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeFile extends PlatformFile {
  _FakeFile(
    this.name,
    this._bytes, {
    this.reportedLength,
    this.lengthKnown = true,
  });

  @override
  final String name;
  final Uint8List _bytes;
  final int? reportedLength;
  final bool lengthKnown;
  int reads = 0;

  @override
  Uri get uri => Uri.parse('memory://$name');
  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);
  @override
  int? lengthSync() => reportedLength;
  @override
  Future<int?> length() async => lengthKnown ? _bytes.length : null;
  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return _bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

void main() {
  group('readPickedFile', () {
    test('returns name and bytes for a file within the limit', () async {
      final f = _FakeFile(
        'leads.csv',
        Uint8List.fromList([1, 2, 3]),
        reportedLength: 3,
      );
      final picked = await readPickedFile(f, maxBytes: 10);
      expect(picked.name, 'leads.csv');
      expect(picked.bytes, [1, 2, 3]);
    });

    test('rejects an oversized file before reading its bytes', () async {
      final f = _FakeFile('big.pdf', Uint8List(4), reportedLength: 50);
      await expectLater(
        readPickedFile(f, maxBytes: 10),
        throwsA(
          isA<FileTooLargeException>().having(
            (e) => e.maxBytes,
            'maxBytes',
            10,
          ),
        ),
      );
      expect(f.reads, 0);
    });

    test(
      'falls back to length() when the picker did not report a size',
      () async {
        final f = _FakeFile('big.pdf', Uint8List(20));
        await expectLater(
          readPickedFile(f, maxBytes: 10),
          throwsA(isA<FileTooLargeException>()),
        );
        expect(f.reads, 0);
      },
    );

    test('still enforces the limit when no size is known up front', () async {
      final f = _FakeFile('big.pdf', Uint8List(20), lengthKnown: false);
      await expectLater(
        readPickedFile(f, maxBytes: 10),
        throwsA(isA<FileTooLargeException>()),
      );
    });

    test('a file exactly at the limit is accepted', () async {
      final f = _FakeFile('ok.pdf', Uint8List(10), reportedLength: 10);
      expect((await readPickedFile(f, maxBytes: 10)).bytes.length, 10);
    });
  });
}
