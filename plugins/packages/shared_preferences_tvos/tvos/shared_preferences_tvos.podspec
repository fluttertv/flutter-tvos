#
# CocoaPods spec for shared_preferences_tvos.
#
# Note: `s.dependency 'Flutter'` is not used because the Flutter pod does not
# declare tvOS support. Instead we point FRAMEWORK_SEARCH_PATHS at the
# app's Flutter framework directory so the plugin can import Flutter at
# build time.
#
Pod::Spec.new do |s|
  s.name             = 'shared_preferences_tvos'
  s.version          = '0.1.0'
  s.summary          = 'tvOS implementation of shared_preferences, backed by NSUserDefaults.'
  s.description      = <<-DESC
tvOS implementation of the shared_preferences plugin. Values are persisted
to NSUserDefaults on the "flutter." namespace, matching the iOS / macOS
behaviour of the upstream plugin.
                       DESC
  s.homepage         = 'https://github.com/fluttertv/plugins'
  s.license          = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author           = { 'FlutterTV' => 'hello@fluttertv.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.swift_version    = '5.0'

  s.platform         = :tvos, '13.0'
  s.tvos.deployment_target = '13.0'

  s.xcconfig = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"',
    'OTHER_LDFLAGS' => '-framework Flutter',
    'DEFINES_MODULE' => 'YES',
  }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '3',
  }
end
