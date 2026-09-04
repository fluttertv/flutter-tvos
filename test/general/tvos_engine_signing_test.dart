// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tvos/tvos_engine_signing.dart';

import '../src/common.dart';
import '../src/fake_process_manager.dart';

/// `security find-identity -v -p codesigning` output with the shapes that
/// matter: a Developer ID, and two development certificates sharing one display
/// name (a renewed cert alongside the one it replaced).
const String _identities = '''
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Someone (ABCDE12345)"
  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Apple Development: Someone (ABCDE12345)"
  3) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Apple Distribution: Someone (TEAM123456)"
  4) DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD "Developer ID Application: Someone (TEAM123456)"
     4 valid identities found
''';

/// The ordinary tvOS developer: an Apple Distribution certificate (required to
/// upload at all) and no Developer ID, which only an Account Holder can create.
const String _distributionOnly = '''
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Someone (ABCDE12345)"
  2) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Apple Distribution: Someone (TEAM123456)"
     2 valid identities found
''';

const String _noDeveloperId = '''
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Someone (ABCDE12345)"
     1 valid identity found
''';

/// A revoked certificate. `find-identity` annotates it but still counts it in
/// the "valid identities found" total, and it is listed *before* the good one
/// so that taking the first match would pick the wrong certificate.
const String _revokedFirst = '''
  1) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "Apple Distribution: Someone (TEAM123456)" (CSSMERR_TP_CERT_REVOKED)
  2) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Apple Distribution: Someone (TEAM123456)"
     2 valid identities found
''';

const String _revokedOnly = '''
  1) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "Apple Distribution: Someone (TEAM123456)" (CSSMERR_TP_CERT_REVOKED)
     1 valid identity found
''';

const List<String> _findIdentity = <String>[
  'security',
  'find-identity',
  '-v',
  '-p',
  'codesigning',
];

TvosEngineSigner _signer({
  required FileSystem fs,
  required FakeProcessManager pm,
  required Logger logger,
  Map<String, String> environment = const <String, String>{},
}) {
  return TvosEngineSigner(
    fileSystem: fs,
    processManager: pm,
    logger: logger,
    platform: FakePlatform(environment: environment),
  );
}

/// An engine variant directory with both the standalone framework and the
/// xcframework slice, which is what a real `engine_artifacts/<variant>` holds.
Directory _variant(FileSystem fs) {
  final Directory dir = fs.directory('/artifacts/tvos_release_arm64');
  dir.childDirectory('Flutter.framework').createSync(recursive: true);
  dir
      .childDirectory('Flutter.xcframework')
      .childDirectory('tvos-arm64')
      .childDirectory('Flutter.framework')
      .createSync(recursive: true);
  return dir;
}

void main() {
  late MemoryFileSystem fileSystem;
  late BufferLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    logger = BufferLogger.test();
  });

  group('identity resolution', () {
    testWithoutContext('uses the Apple Distribution certificate', () {
      // The regression that broke 1.9.0 for customers: artifacts ship unsigned
      // and the CLI signs locally, but it only accepted a certificate most
      // tvOS developers cannot obtain, so their engine shipped unsigned and
      // Apple rejected it with ITMS-91065.
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _distributionOnly),
      ]);
      final ({String hash, String name})? identity =
          _signer(fs: fileSystem, pm: pm, logger: logger).resolveIdentity();
      expect(identity?.name, 'Apple Distribution: Someone (TEAM123456)');
      expect(identity?.hash, 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC');
    });

    testWithoutContext('picks Apple Distribution even when a Developer ID is present', () {
      // Developer ID also satisfies the check, but it is not accepted: it is a
      // certificate almost no tvOS developer holds, so supporting it would add
      // a branch that practically never fires.
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _identities),
      ]);
      expect(
        _signer(fs: fileSystem, pm: pm, logger: logger).resolveIdentity()?.name,
        'Apple Distribution: Someone (TEAM123456)',
      );
    });

    testWithoutContext('returns null rather than falling back to a development cert', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _noDeveloperId),
      ]);
      expect(_signer(fs: fileSystem, pm: pm, logger: logger).resolveIdentity(), isNull);
    });

    testWithoutContext('skips a revoked certificate in favour of a good one', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _revokedFirst),
      ]);
      final ({String hash, String name})? identity =
          _signer(fs: fileSystem, pm: pm, logger: logger).resolveIdentity();
      // codesign exits 0 with a revoked certificate, so picking it would
      // produce a build that only fails at submission.
      expect(identity?.hash, 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC');
    });

    testWithoutContext('returns null when the only certificate is revoked', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _revokedOnly),
      ]);
      expect(_signer(fs: fileSystem, pm: pm, logger: logger).resolveIdentity(), isNull);
    });

    testWithoutContext('override rejects a revoked certificate named by hash', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _revokedFirst),
      ]);
      expect(
        () => _signer(
          fs: fileSystem,
          pm: pm,
          logger: logger,
          environment: <String, String>{
            TvosEngineSigner.kIdentityEnvVar: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
          },
        ).resolveIdentity(),
        throwsA(isA<StateError>()),
      );
    });

    testWithoutContext('override accepts a SHA-1 hash', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _identities),
      ]);
      final ({String hash, String name})? identity = _signer(
        fs: fileSystem,
        pm: pm,
        logger: logger,
        environment: <String, String>{
          TvosEngineSigner.kIdentityEnvVar: 'cccccccccccccccccccccccccccccccccccccccc',
        },
      ).resolveIdentity();
      expect(identity?.name, 'Apple Distribution: Someone (TEAM123456)');
    });

    testWithoutContext('override rejects a name matching more than one certificate', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _identities),
      ]);
      expect(
        () => _signer(
          fs: fileSystem,
          pm: pm,
          logger: logger,
          environment: <String, String>{
            TvosEngineSigner.kIdentityEnvVar: 'Apple Development: Someone (ABCDE12345)',
          },
        ).resolveIdentity(),
        // Signing by an ambiguous name is what makes codesign fail with
        // "ambiguous (matches ... and ...)", so it is refused up front.
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('SHA-1'))),
      );
    });

    testWithoutContext('override rejects an unknown hash', () {
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _identities),
      ]);
      expect(
        () => _signer(
          fs: fileSystem,
          pm: pm,
          logger: logger,
          environment: <String, String>{
            TvosEngineSigner.kIdentityEnvVar: 'ffffffffffffffffffffffffffffffffffffffff',
          },
        ).resolveIdentity(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('signing', () {
    const ({String hash, String name}) identity = (
      hash: 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',
      name: 'Developer ID Application: Someone (TEAM123456)',
    );

    testWithoutContext('signs inner frameworks before the xcframework wrapper', () {
      final Directory dir = _variant(fileSystem);
      final pm = FakeProcessManager.list(<FakeCommand>[
        // Nothing carries _CodeSignature yet, so no `codesign -dvv` probe runs.
        FakeCommand(
          command: <String>[
            'codesign',
            '--force',
            '--timestamp',
            '--options',
            'runtime',
            '--sign',
            identity.hash,
            '/artifacts/tvos_release_arm64/Flutter.xcframework/tvos-arm64/Flutter.framework',
          ],
        ),
        FakeCommand(
          command: <String>[
            'codesign',
            '--force',
            '--timestamp',
            '--options',
            'runtime',
            '--sign',
            identity.hash,
            '/artifacts/tvos_release_arm64/Flutter.framework',
          ],
        ),
        // The wrapper last, so its seal covers the inner signatures, and
        // without hardened runtime — it has no Mach-O of its own.
        FakeCommand(
          command: <String>[
            'codesign',
            '--force',
            '--timestamp',
            '--sign',
            identity.hash,
            '/artifacts/tvos_release_arm64/Flutter.xcframework',
          ],
        ),
      ]);

      _signer(fs: fileSystem, pm: pm, logger: logger).signVariant(dir, identity);
      expect(pm, hasNoRemainingExpectations);
    });

    testWithoutContext('skips work when already signed by the same identity', () {
      final Directory dir = _variant(fileSystem);
      for (final path in <String>[
        '/artifacts/tvos_release_arm64/Flutter.framework',
        '/artifacts/tvos_release_arm64/Flutter.xcframework/tvos-arm64/Flutter.framework',
      ]) {
        fileSystem.directory('$path/_CodeSignature').createSync(recursive: true);
      }
      final pm = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: const <String>[
            'codesign',
            '-dvv',
            '/artifacts/tvos_release_arm64/Flutter.xcframework/tvos-arm64/Flutter.framework',
          ],
          stderr: 'Authority=${identity.name}\n',
        ),
        FakeCommand(
          command: const <String>[
            'codesign',
            '-dvv',
            '/artifacts/tvos_release_arm64/Flutter.framework',
          ],
          stderr: 'Authority=${identity.name}\n',
        ),
      ]);

      _signer(fs: fileSystem, pm: pm, logger: logger).signVariant(dir, identity);
      expect(pm, hasNoRemainingExpectations);
    });

    testWithoutContext('re-signs when the existing signature is a different identity', () {
      final Directory dir = _variant(fileSystem);
      fileSystem
          .directory('/artifacts/tvos_release_arm64/Flutter.framework/_CodeSignature')
          .createSync(recursive: true);
      final pm = FakeProcessManager.any();

      _signer(fs: fileSystem, pm: pm, logger: logger).signVariant(dir, identity);
      // The probe reports no matching Authority, so signing proceeds; the point
      // is that a foreign signature is replaced rather than trusted.
      expect(logger.traceText, contains('Signed tvOS engine'));
    });
  });

  group('signIfPossible', () {
    testWithoutContext('warns and continues when no Developer ID exists', () {
      final Directory dir = _variant(fileSystem);
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _noDeveloperId),
      ]);

      _signer(fs: fileSystem, pm: pm, logger: logger).signIfPossible(dir);

      // A developer without the certificate must still get a working build;
      // only submission needs the signature.
      expect(logger.statusText, contains('ITMS-91065'));
      expect(pm, hasNoRemainingExpectations);
    });

    testWithoutContext('does nothing when skipping is requested', () {
      final Directory dir = _variant(fileSystem);
      final pm = FakeProcessManager.empty();

      _signer(
        fs: fileSystem,
        pm: pm,
        logger: logger,
        environment: <String, String>{TvosEngineSigner.kSkipEnvVar: '1'},
      ).signIfPossible(dir);

      expect(pm, hasNoRemainingExpectations);
    });

    testWithoutContext('does not fail the build when codesign fails', () {
      final Directory dir = _variant(fileSystem);
      final pm = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(command: _findIdentity, stdout: _identities),
        const FakeCommand(
          command: <String>[
            'codesign',
            '--force',
            '--timestamp',
            '--options',
            'runtime',
            '--sign',
            'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
            '/artifacts/tvos_release_arm64/Flutter.xcframework/tvos-arm64/Flutter.framework',
          ],
          exitCode: 1,
          stderr: 'errSecInternalComponent',
        ),
      ]);

      _signer(fs: fileSystem, pm: pm, logger: logger).signIfPossible(dir);

      expect(logger.errorText, contains('ITMS-91065'));
    });
  });
}
