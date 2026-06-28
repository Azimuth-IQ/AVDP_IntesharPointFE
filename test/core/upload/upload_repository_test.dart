// Tests for the pure [mimeTypeForFilename] helper in upload_repository.dart.
//
// No new dependencies — uses only flutter_test (already in dev_dependencies)
// and the production library under test.  No network, Dio, or widget setup is
// needed because [mimeTypeForFilename] is a pure function.

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/upload/upload_repository.dart';

void main() {
  group('mimeTypeForFilename — known image types', () {
    test('jpg → image/jpeg', () {
      expect(mimeTypeForFilename('photo.jpg'), 'image/jpeg');
    });

    test('jpeg → image/jpeg', () {
      expect(mimeTypeForFilename('photo.jpeg'), 'image/jpeg');
    });

    test('png → image/png', () {
      expect(mimeTypeForFilename('logo.png'), 'image/png');
    });

    test('gif → image/gif', () {
      expect(mimeTypeForFilename('anim.gif'), 'image/gif');
    });

    test('webp → image/webp', () {
      expect(mimeTypeForFilename('banner.webp'), 'image/webp');
    });

    test('svg → image/svg+xml', () {
      expect(mimeTypeForFilename('icon.svg'), 'image/svg+xml');
    });
  });

  group('mimeTypeForFilename — document types', () {
    test('pdf → application/pdf', () {
      expect(mimeTypeForFilename('contract.pdf'), 'application/pdf');
    });
  });

  group('mimeTypeForFilename — extension case folding', () {
    test('JPG (upper-case) → image/jpeg', () {
      expect(mimeTypeForFilename('PHOTO.JPG'), 'image/jpeg');
    });

    test('PNG (upper-case) → image/png', () {
      expect(mimeTypeForFilename('Logo.PNG'), 'image/png');
    });
  });

  group('mimeTypeForFilename — edge cases', () {
    test('unknown extension → application/octet-stream', () {
      expect(mimeTypeForFilename('data.bin'), 'application/octet-stream');
    });

    test('no extension → application/octet-stream', () {
      expect(mimeTypeForFilename('noextension'), 'application/octet-stream');
    });

    test('multiple dots — uses last segment', () {
      expect(mimeTypeForFilename('my.archive.tar.gz'), 'application/octet-stream');
    });

    test('dotfile with no real ext → application/octet-stream', () {
      // ".gitignore" → ext = "gitignore" which is unknown
      expect(mimeTypeForFilename('.gitignore'), 'application/octet-stream');
    });

    test('file.png — compound name still picks up png', () {
      expect(mimeTypeForFilename('company.logo.png'), 'image/png');
    });
  });
}
