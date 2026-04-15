import 'package:flutter/material.dart';
import 'package:flutter_tvos/flutter_tvos.dart';

void main() {
  runApp(const FlutterTvosExampleApp());
}

class FlutterTvosExampleApp extends StatelessWidget {
  const FlutterTvosExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_tvos Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PlatformInfoScreen(),
    );
  }
}

class PlatformInfoScreen extends StatelessWidget {
  const PlatformInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // All calls are synchronous — dart:ffi, no async needed.
    return Scaffold(
      appBar: AppBar(title: const Text('tvOS Platform Info')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _InfoTile(label: 'Is tvOS', value: '${TvOSInfo.isTvOS}'),
          _InfoTile(label: 'tvOS Version', value: TvOSInfo.tvOSVersion),
          _InfoTile(label: 'Device Model', value: TvOSInfo.deviceModel),
          _InfoTile(label: 'Machine ID', value: TvOSInfo.machineId),
          _InfoTile(label: 'Is Simulator', value: '${TvOSInfo.isSimulator}'),
          _InfoTile(label: 'Supports 4K', value: '${TvOSInfo.supports4K}'),
          _InfoTile(label: 'Supports HDR', value: '${TvOSInfo.supportsHDR}'),
          _InfoTile(label: 'Multi-User', value: '${TvOSInfo.supportsMultiUser}'),
          _InfoTile(label: 'Display Resolution', value: TvOSInfo.displayResolution),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}
