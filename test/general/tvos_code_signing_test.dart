// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/tvos_build_info.dart';

import '../src/common.dart';
import '../src/context.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
  });

  group('Code signing - team ID from pbxproj', () {
    testUsingContext(
      'extracts DEVELOPMENT_TEAM from project.pbxproj',
      () {
        final Directory tvosDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);
        final File pbxproj = tvosDir.childDirectory('Runner.xcodeproj').childFile('project.pbxproj')
          ..createSync(recursive: true);

        pbxproj.writeAsStringSync('''
/* Build configuration list for PBXNativeTarget "Runner" */
buildSettings = {
  ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
  DEVELOPMENT_TEAM = ABC1234567;
  INFOPLIST_FILE = Runner/Info.plist;
  PRODUCT_BUNDLE_IDENTIFIER = com.example.runner;
};
''');

        final String content = pbxproj.readAsStringSync();
        final teamRegex = RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10});');
        final Match? match = teamRegex.firstMatch(content);

        expect(match, isNotNull);
        expect(match!.group(1), equals('ABC1234567'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'returns null when no DEVELOPMENT_TEAM in pbxproj',
      () {
        final Directory tvosDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);
        final File pbxproj = tvosDir.childDirectory('Runner.xcodeproj').childFile('project.pbxproj')
          ..createSync(recursive: true);

        pbxproj.writeAsStringSync('''
buildSettings = {
  PRODUCT_BUNDLE_IDENTIFIER = com.example.runner;
};
''');

        final String content = pbxproj.readAsStringSync();
        final teamRegex = RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10});');
        final Match? match = teamRegex.firstMatch(content);

        expect(match, isNull);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'returns null when pbxproj does not exist',
      () {
        final Directory tvosDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);

        final File pbxproj = tvosDir
            .childDirectory('Runner.xcodeproj')
            .childFile('project.pbxproj');

        expect(pbxproj.existsSync(), isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('Code signing - keychain identity parsing', () {
    testWithoutContext('extracts team ID from security find-identity output', () {
      const securityOutput = '''
  1) AABBCCDDEE1122334455 "Apple Development: John Doe (XYZ9876543)"
  2) FFEEDDCCBBAA5544332211 "Apple Distribution: ACME Corp (XYZ9876543)"
     2 valid identities found
''';

      final identityRegex = RegExp(r'Apple Development:.*\(([A-Z0-9]{10})\)');
      final Match? match = identityRegex.firstMatch(securityOutput);

      expect(match, isNotNull);
      expect(match!.group(1), equals('XYZ9876543'));
    });

    testWithoutContext('returns null when no Apple Development identity found', () {
      const securityOutput = '''
  1) FFEEDDCCBBAA5544332211 "Apple Distribution: ACME Corp (XYZ9876543)"
     1 valid identities found
''';

      final identityRegex = RegExp(r'Apple Development:.*\(([A-Z0-9]{10})\)');
      final Match? match = identityRegex.firstMatch(securityOutput);

      expect(match, isNull);
    });

    testWithoutContext('returns null for empty keychain output', () {
      const securityOutput = '     0 valid identities found\n';

      final identityRegex = RegExp(r'Apple Development:.*\(([A-Z0-9]{10})\)');
      final Match? match = identityRegex.firstMatch(securityOutput);

      expect(match, isNull);
    });
  });

  group('Code signing - App Store Connect API key', () {
    late BufferLogger logger;

    setUp(() {
      logger = BufferLogger.test();
    });

    Map<String, String> env({String? path, String? id, String? issuer, String? home}) {
      return <String, String>{
        if (path != null) 'APP_STORE_CONNECT_KEY_PATH': path,
        if (id != null) 'APP_STORE_CONNECT_KEY_ID': id,
        if (issuer != null) 'APP_STORE_CONNECT_ISSUER_ID': issuer,
        if (home != null) 'HOME': home,
      };
    }

    testWithoutContext('forwards the key when all three are set', () {
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);

      expect(
        resolveAuthenticationArgs(
          env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567', issuer: 'issuer-uuid'),
          fileSystem,
          logger,
        ),
        <String>[
          '-authenticationKeyPath',
          '/keys/AuthKey_ABC.p8',
          '-authenticationKeyID',
          'ABC1234567',
          '-authenticationKeyIssuerID',
          'issuer-uuid',
        ],
      );
    });

    testWithoutContext('announces the key id at default verbosity', () {
      // printTrace is a no-op in StdoutLogger, so tracing this would leave
      // "working", "half-configured" and "never configured" indistinguishable
      // from the log at default verbosity.
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);

      resolveAuthenticationArgs(
        env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567', issuer: 'issuer-uuid'),
        fileSystem,
        logger,
      );

      expect(logger.statusText, contains('ABC1234567'));
    });

    testWithoutContext('is inert and silent when nothing is set', () {
      // The common case: a machine with a working Xcode account must behave
      // exactly as it did before this existed, and must not be nagged.
      expect(
        resolveAuthenticationArgs(<String, String>{}, fileSystem, logger),
        isEmpty,
      );
      expect(logger.warningText, isEmpty);
      expect(logger.statusText, isEmpty);
    });

    testWithoutContext('is inert when the trio is incomplete', () {
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);
      // A half-configured environment must not produce half a flag set --
      // xcodebuild rejects the key arguments unless all three are present.
      expect(
        resolveAuthenticationArgs(
          env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567'),
          fileSystem,
          logger,
        ),
        isEmpty,
      );
      expect(
        resolveAuthenticationArgs(
          env(path: '/keys/AuthKey_ABC.p8', issuer: 'issuer-uuid'),
          fileSystem,
          logger,
        ),
        isEmpty,
      );
    });

    testWithoutContext('warns which variable is missing when partly configured', () {
      // Silence here is the same failure this function exists to prevent:
      // indistinguishable from never having configured it, and the build dies
      // minutes later with the misleading capability error.
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);

      expect(
        resolveAuthenticationArgs(
          env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567'),
          fileSystem,
          logger,
        ),
        isEmpty,
      );
      expect(logger.warningText, contains('APP_STORE_CONNECT_ISSUER_ID'));
      expect(logger.warningText, isNot(contains('APP_STORE_CONNECT_KEY_PATH is set')));
    });

    testWithoutContext('warns when a CI secret interpolates to the empty string', () {
      // An undefined GitHub Actions secret arrives as "", not as an absent
      // variable: all three are set, the operator has demonstrably configured
      // this, and treating it as unconfigured loses the only useful signal.
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);

      for (final environment in <Map<String, String>>[
        env(path: '', id: 'ABC1234567', issuer: 'issuer-uuid'),
        env(path: '/keys/AuthKey_ABC.p8', id: '', issuer: 'issuer-uuid'),
        env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567', issuer: ''),
      ]) {
        logger.clear();
        expect(resolveAuthenticationArgs(environment, fileSystem, logger), isEmpty);
        expect(logger.warningText, contains('partly configured'));
      }
    });

    testWithoutContext('names the asymmetric issuer variable in the warning', () {
      // APP_STORE_CONNECT_KEY_PATH, _KEY_ID, then _ISSUER_ID: the `KEY_` is
      // dropped, so APP_STORE_CONNECT_KEY_ISSUER_ID is the natural guess and
      // is silently ignored.
      resolveAuthenticationArgs(
        <String, String>{'APP_STORE_CONNECT_KEY_ISSUER_ID': 'issuer-uuid'},
        fileSystem,
        logger,
      );
      expect(logger.warningText, isEmpty);

      resolveAuthenticationArgs(
        env(path: '/keys/AuthKey_ABC.p8', id: 'ABC1234567'),
        fileSystem,
        logger,
      );
      expect(logger.warningText, contains('not APP_STORE_CONNECT_KEY_ISSUER_ID'));
    });

    testWithoutContext('trims values that arrive with a trailing newline', () {
      // `KEY_ID=$(cat keyid)` and most secret stores append one. In a path the
      // newline is invisible, so the resulting warning looks nonsensical.
      fileSystem.file('/keys/AuthKey_ABC.p8').createSync(recursive: true);

      expect(
        resolveAuthenticationArgs(
          env(
            path: '/keys/AuthKey_ABC.p8\n',
            id: 'ABC1234567\n',
            issuer: 'issuer-uuid\n',
          ),
          fileSystem,
          logger,
        ),
        <String>[
          '-authenticationKeyPath',
          '/keys/AuthKey_ABC.p8',
          '-authenticationKeyID',
          'ABC1234567',
          '-authenticationKeyIssuerID',
          'issuer-uuid',
        ],
      );
    });

    testWithoutContext('expands a leading tilde against HOME', () {
      // A CI `env:` block, a quoted assignment, a `.env` file and an Xcode
      // scheme variable all deliver a literal `~`, which would otherwise
      // resolve to `/~/...` and never exist.
      fileSystem.file('/Users/dev/.appstoreconnect/AuthKey_ABC.p8').createSync(recursive: true);

      expect(
        resolveAuthenticationArgs(
          env(
            path: '~/.appstoreconnect/AuthKey_ABC.p8',
            id: 'ABC1234567',
            issuer: 'issuer-uuid',
            home: '/Users/dev',
          ),
          fileSystem,
          logger,
        ),
        containsAllInOrder(<String>[
          '-authenticationKeyPath',
          '/Users/dev/.appstoreconnect/AuthKey_ABC.p8',
        ]),
      );
    });

    testWithoutContext('blames the tilde when there is no HOME to expand it against', () {
      expect(
        resolveAuthenticationArgs(
          env(path: '~/keys/AuthKey_ABC.p8', id: 'ABC1234567', issuer: 'issuer-uuid'),
          fileSystem,
          logger,
        ),
        isEmpty,
      );
      expect(logger.warningText, contains('`~`'));
    });

    testWithoutContext('makes a relative key path absolute', () {
      // existsSync resolves against this process's cwd, but xcodebuild runs
      // with workingDirectory: tvosProjectDir.path -- so a relative path that
      // passes the check here would be handed over one directory deeper.
      fileSystem.currentDirectory = fileSystem.directory('/work')..createSync();
      fileSystem.file('/work/keys/AuthKey_ABC.p8').createSync(recursive: true);

      expect(
        resolveAuthenticationArgs(
          env(path: 'keys/AuthKey_ABC.p8', id: 'ABC1234567', issuer: 'issuer-uuid'),
          fileSystem,
          logger,
        ),
        containsAllInOrder(<String>[
          '-authenticationKeyPath',
          '/work/keys/AuthKey_ABC.p8',
        ]),
      );
    });

    testWithoutContext('warns, and falls back, when the key file is missing', () {
      // Configured but wrong is the case worth a warning: staying silent looks
      // identical to never having configured it, and the build then fails much
      // later complaining about a capability rather than a credential.
      expect(
        resolveAuthenticationArgs(
          env(path: '/keys/absent.p8', id: 'ABC1234567', issuer: 'issuer-uuid'),
          fileSystem,
          logger,
        ),
        isEmpty,
      );
      expect(logger.warningText, contains('/keys/absent.p8'));
    });
  });

  group('Code signing - xcodebuild argument wiring', () {
    List<String> args({
      bool isSimulator = false,
      bool codesign = true,
      List<String> signingArgs = const <String>[],
      List<String> authenticationArgs = const <String>[],
    }) {
      return NativeTvosBundle.xcodebuildArgs(
        hasWorkspace: false,
        configuration: 'Release',
        sdkName: isSimulator ? 'appletvsimulator' : 'appletvos',
        symroot: '/build',
        isSimulator: isSimulator,
        signingArgs: signingArgs,
        authenticationArgs: authenticationArgs,
        codesign: codesign,
      );
    }

    testWithoutContext('a device build forwards the authentication arguments', () {
      // Without this, the whole feature can be unhooked from the build and
      // every test of resolveAuthenticationArgs still passes.
      expect(
        args(authenticationArgs: <String>[
          '-authenticationKeyPath',
          '/keys/AuthKey_ABC.p8',
          '-authenticationKeyID',
          'ABC1234567',
          '-authenticationKeyIssuerID',
          'issuer-uuid',
        ]),
        containsAllInOrder(<String>[
          '-allowProvisioningUpdates',
          '-authenticationKeyPath',
          '/keys/AuthKey_ABC.p8',
          '-authenticationKeyID',
          'ABC1234567',
          '-authenticationKeyIssuerID',
          'issuer-uuid',
        ]),
      );
    });

    testWithoutContext('a simulator build carries neither signing nor authentication', () {
      // The simulator is never code-signed, so -allowProvisioningUpdates has
      // nothing to update and a key has nothing to authenticate for.
      final List<String> simulatorArgs = args(
        isSimulator: true,
        signingArgs: <String>['DEVELOPMENT_TEAM=XYZ9876543'],
        authenticationArgs: <String>['-authenticationKeyID', 'ABC1234567'],
      );

      expect(simulatorArgs, isNot(contains('-allowProvisioningUpdates')));
      expect(simulatorArgs, isNot(contains('-authenticationKeyID')));
      expect(simulatorArgs, isNot(contains('ABC1234567')));
    });

    testWithoutContext('signing arguments reach xcodebuild on a device build', () {
      expect(
        args(signingArgs: <String>['DEVELOPMENT_TEAM=XYZ9876543', 'CODE_SIGN_STYLE=Automatic']),
        containsAllInOrder(<String>['DEVELOPMENT_TEAM=XYZ9876543', 'CODE_SIGN_STYLE=Automatic']),
      );
    });

    testWithoutContext('--no-codesign drops provisioning from a device build', () {
      // -allowProvisioningUpdates is the flag that sends xcodebuild to the
      // developer portal for a profile. An unsigned build has no profile to
      // fetch, and the machine running one typically has no account to fetch
      // it with, so leaving the flag on is how an unsigned CI build turns into
      // a signing error anyway.
      final List<String> unsigned = args(
        codesign: false,
        authenticationArgs: <String>['-authenticationKeyID', 'ABC1234567'],
      );

      expect(unsigned, isNot(contains('-allowProvisioningUpdates')));
      expect(unsigned, isNot(contains('-authenticationKeyID')));
    });

    testWithoutContext('selects the project or the workspace', () {
      expect(args(), containsAllInOrder(<String>['-project', 'Runner.xcodeproj']));
      expect(
        NativeTvosBundle.xcodebuildArgs(
          hasWorkspace: true,
          configuration: 'Release',
          sdkName: 'appletvos',
          symroot: '/build',
          isSimulator: false,
          signingArgs: const <String>[],
          authenticationArgs: const <String>[],
        ),
        containsAllInOrder(<String>['-workspace', 'Runner.xcworkspace']),
      );
    });

    testWithoutContext('ends with the build action', () {
      expect(args().first, 'xcodebuild');
      expect(args().last, 'build');
    });
  });

  group('Code signing - what --no-codesign actually passes', () {
    // The group above pins the PLUMBING: that `codesign` reaches xcodebuildArgs
    // and drops -allowProvisioningUpdates. This one pins the PAYLOAD: which
    // build settings the resolver returns. Both are needed. With only the
    // former, every one of these five settings could be deleted, or the
    // `!codesign` branch bypassed entirely, and the suite stayed green --
    // verified by mutation. They are exercised for real only on a machine with
    // no certificate, which is not where anyone runs the suite, so a regression
    // would surface as a red CI build in release-train rather than a red test.

    NativeTvosBundle bundle({bool codesign = true, bool simulator = false}) =>
        NativeTvosBundle(
          TvosBuildInfo(
            const BuildInfo(
              BuildMode.release,
              null,
              treeShakeIcons: false,
              packageConfigPath: '.dart_tool/package_config.json',
            ),
            targetArch: 'arm64',
            simulator: simulator,
            codesign: codesign,
          ),
          'lib/main.dart',
        );

    testUsingContext(
      'an unsigned device build passes exactly the five settings that make it work',
      () async {
        expect(
          await bundle(codesign: false).resolveSigningArgs(
            fileSystem.directory('tvos')..createSync(recursive: true),
            false,
            codesign: false,
          ),
          // Not containsAll: the claim in the source comment is that every one
          // of these is required, so the exact list is the assertion. Adding a
          // setting to production code should make a reviewer look here.
          equals(<String>[
            'CODE_SIGNING_ALLOWED=NO',
            'CODE_SIGNING_REQUIRED=NO',
            'CODE_SIGN_IDENTITY=',
            'CODE_SIGN_ENTITLEMENTS=',
            'EXPANDED_CODE_SIGN_IDENTITY=',
          ]),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'refuses to sign even when a team is there for the taking',
      () async {
        // The mutation this exists to catch is bypassing the `!codesign`
        // branch. Without a team in the environment that mutation falls
        // through to keychain discovery and still returns something empty-ish;
        // with one, it returns DEVELOPMENT_TEAM and the difference is loud.
        expect(
          await bundle(codesign: false).resolveSigningArgs(
            fileSystem.directory('tvos')..createSync(recursive: true),
            false,
            codesign: false,
          ),
          isNot(contains('DEVELOPMENT_TEAM=ABC1234567')),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        Platform: () => FakePlatform(
          environment: <String, String>{'DEVELOPMENT_TEAM': 'ABC1234567'},
        ),
      },
    );

    testUsingContext(
      'says so, because an unsigned artifact cannot be installed',
      () async {
        await bundle(codesign: false).resolveSigningArgs(
          fileSystem.directory('tvos')..createSync(recursive: true),
          false,
          codesign: false,
        );
        expect(testLogger.statusText, contains('--no-codesign'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'a simulator build carries no signing settings either way',
      () async {
        for (final codesign in <bool>[true, false]) {
          expect(
            await bundle(codesign: codesign, simulator: true)
                .resolveSigningArgs(
              fileSystem.directory('tvos')..createSync(recursive: true),
              true,
              codesign: codesign,
            ),
            isEmpty,
            reason: 'simulator, codesign: $codesign',
          );
        }
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  // The former 'Code signing - simulator vs device' group lived here. Both of
  // its cases asserted against local constants -- `expect(const <String>[],
  // isEmpty)` and `expect(isSimulator, isFalse)` -- so neither could fail, and
  // neither reached production code. The 'xcodebuild argument wiring' group
  // above makes the same two claims against NativeTvosBundle.xcodebuildArgs.
}
