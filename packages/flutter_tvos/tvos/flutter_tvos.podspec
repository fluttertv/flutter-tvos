Pod::Spec.new do |s|
  s.name             = 'flutter_tvos'
  s.version          = '1.0.0'
  s.summary          = 'Platform detection and utilities for Flutter on tvOS (FFI).'
  s.description      = <<-DESC
Provides runtime checks to determine if a Flutter app is running on Apple TV (tvOS),
along with device information, capability queries, and display details.
Uses dart:ffi for synchronous native calls with zero async overhead.
                       DESC
  s.homepage         = 'https://fluttertv.dev'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'FlutterTV' => 'info@fluttertv.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/flutter_tvos_ffi.{h,m}'
  s.public_header_files = 'Classes/flutter_tvos_ffi.h'

  s.platform         = :tvos, '13.0'

  s.frameworks       = 'UIKit', 'Foundation'
  s.tvos.deployment_target = '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end
