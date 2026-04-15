import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/flutter_tvos.dart';

/// A fake [TvOSNativeBindings] for testing without actual FFI calls.
class FakeTvOSNativeBindings extends TvOSNativeBindings {
  FakeTvOSNativeBindings({
    this.fakeIsTvOS = false,
    this.fakeSystemVersion = '',
    this.fakeDeviceModel = '',
    this.fakeMachineId = '',
    this.fakeIsSimulator = false,
    this.fakeSupports4K = false,
    this.fakeSupportsHDR = false,
    this.fakeSupportsMultiUser = false,
    this.fakeDisplayWidth = 0,
    this.fakeDisplayHeight = 0,
  }) : super.forTesting();

  final bool fakeIsTvOS;
  final String fakeSystemVersion;
  final String fakeDeviceModel;
  final String fakeMachineId;
  final bool fakeIsSimulator;
  final bool fakeSupports4K;
  final bool fakeSupportsHDR;
  final bool fakeSupportsMultiUser;
  final int fakeDisplayWidth;
  final int fakeDisplayHeight;

  @override
  bool get isTvOS => fakeIsTvOS;

  @override
  String get systemVersion => fakeSystemVersion;

  @override
  String get deviceModel => fakeDeviceModel;

  @override
  String get machineId => fakeMachineId;

  @override
  bool get isSimulator => fakeIsSimulator;

  @override
  bool get supports4K => fakeSupports4K;

  @override
  bool get supportsHDR => fakeSupportsHDR;

  @override
  bool get supportsMultiUser => fakeSupportsMultiUser;

  @override
  int get displayWidth => fakeDisplayWidth;

  @override
  int get displayHeight => fakeDisplayHeight;

  @override
  String get displayResolution => '${fakeDisplayWidth}x$fakeDisplayHeight';
}

void main() {
  setUp(() {
    TvOSInfo.bindingsOverride = null;
  });

  tearDown(() {
    TvOSInfo.bindingsOverride = null;
  });

  group('TvOSInfo', () {
    group('when running on tvOS device', () {
      setUp(() {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: true,
          fakeIsSimulator: false,
          fakeSystemVersion: '18.4',
          fakeDeviceModel: 'Apple TV',
          fakeMachineId: 'AppleTV14,1',
          fakeSupports4K: true,
          fakeSupportsHDR: true,
          fakeSupportsMultiUser: true,
          fakeDisplayWidth: 3840,
          fakeDisplayHeight: 2160,
        );
      });

      test('isTvOS returns true', () {
        expect(TvOSInfo.isTvOS, isTrue);
      });

      test('tvOSVersion returns version string', () {
        expect(TvOSInfo.tvOSVersion, '18.4');
      });

      test('deviceModel returns model name', () {
        expect(TvOSInfo.deviceModel, 'Apple TV');
      });

      test('machineId returns identifier', () {
        expect(TvOSInfo.machineId, 'AppleTV14,1');
      });

      test('isSimulator returns false on device', () {
        expect(TvOSInfo.isSimulator, isFalse);
      });

      test('supports4K returns true for 4K device', () {
        expect(TvOSInfo.supports4K, isTrue);
      });

      test('supportsHDR returns true', () {
        expect(TvOSInfo.supportsHDR, isTrue);
      });

      test('supportsMultiUser returns true for tvOS 14+', () {
        expect(TvOSInfo.supportsMultiUser, isTrue);
      });

      test('displayResolution returns resolution string', () {
        expect(TvOSInfo.displayResolution, '3840x2160');
      });

      test('displayWidth returns pixel width', () {
        expect(TvOSInfo.displayWidth, 3840);
      });

      test('displayHeight returns pixel height', () {
        expect(TvOSInfo.displayHeight, 2160);
      });
    });

    group('when running on tvOS Simulator', () {
      setUp(() {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: true,
          fakeIsSimulator: true,
          fakeSystemVersion: '18.4',
          fakeDeviceModel: 'Apple TV',
          fakeMachineId: 'arm64',
          fakeSupports4K: false,
          fakeSupportsHDR: false,
          fakeSupportsMultiUser: true,
          fakeDisplayWidth: 1920,
          fakeDisplayHeight: 1080,
        );
      });

      test('isTvOS returns true', () {
        expect(TvOSInfo.isTvOS, isTrue);
      });

      test('isSimulator returns true', () {
        expect(TvOSInfo.isSimulator, isTrue);
      });

      test('supports4K returns false in simulator', () {
        expect(TvOSInfo.supports4K, isFalse);
      });

      test('displayResolution returns 1080p', () {
        expect(TvOSInfo.displayResolution, '1920x1080');
      });
    });

    group('when running on non-tvOS platform', () {
      setUp(() {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: false,
          fakeIsSimulator: false,
          fakeSystemVersion: '17.0',
          fakeDeviceModel: 'iPhone',
          fakeMachineId: 'iPhone15,2',
          fakeSupports4K: false,
          fakeSupportsHDR: false,
          fakeSupportsMultiUser: false,
          fakeDisplayWidth: 2556,
          fakeDisplayHeight: 1179,
        );
      });

      test('isTvOS returns false', () {
        expect(TvOSInfo.isTvOS, isFalse);
      });

      test('deviceModel returns non-tvOS model', () {
        expect(TvOSInfo.deviceModel, 'iPhone');
      });
    });

    group('bindingsOverride', () {
      test('allows replacing bindings for testing', () {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: true,
          fakeSystemVersion: '18.0',
        );
        expect(TvOSInfo.isTvOS, isTrue);
        expect(TvOSInfo.tvOSVersion, '18.0');

        // Replace with different bindings
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: false,
          fakeSystemVersion: '17.0',
        );
        expect(TvOSInfo.isTvOS, isFalse);
        expect(TvOSInfo.tvOSVersion, '17.0');
      });

      test('setting null creates fresh real bindings on next access', () {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(fakeIsTvOS: true);
        expect(TvOSInfo.isTvOS, isTrue);

        TvOSInfo.bindingsOverride = null;
        // Next access would create real TvOSNativeBindings.
        // We can't test the real bindings in unit tests (no native libs),
        // so just verify the override was cleared.
      });
    });

    group('synchronous API', () {
      test('all getters are synchronous (no Future)', () {
        TvOSInfo.bindingsOverride = FakeTvOSNativeBindings(
          fakeIsTvOS: true,
          fakeSystemVersion: '18.4',
          fakeDeviceModel: 'Apple TV',
          fakeMachineId: 'AppleTV14,1',
          fakeIsSimulator: true,
          fakeSupports4K: true,
          fakeSupportsHDR: true,
          fakeSupportsMultiUser: true,
          fakeDisplayWidth: 3840,
          fakeDisplayHeight: 2160,
        );

        // These are all sync — no await needed
        final bool isTvOS = TvOSInfo.isTvOS;
        final String version = TvOSInfo.tvOSVersion;
        final String model = TvOSInfo.deviceModel;
        final String machineId = TvOSInfo.machineId;
        final bool isSim = TvOSInfo.isSimulator;
        final bool is4K = TvOSInfo.supports4K;
        final bool isHDR = TvOSInfo.supportsHDR;
        final bool isMultiUser = TvOSInfo.supportsMultiUser;
        final int width = TvOSInfo.displayWidth;
        final int height = TvOSInfo.displayHeight;
        final String res = TvOSInfo.displayResolution;

        expect(isTvOS, isTrue);
        expect(version, '18.4');
        expect(model, 'Apple TV');
        expect(machineId, 'AppleTV14,1');
        expect(isSim, isTrue);
        expect(is4K, isTrue);
        expect(isHDR, isTrue);
        expect(isMultiUser, isTrue);
        expect(width, 3840);
        expect(height, 2160);
        expect(res, '3840x2160');
      });
    });
  });
}
