import 'package:flutter/material.dart';
import 'package:flutter_tvos/flutter_tvos.dart';

void main() => runTvApp(const FlutterTvosExampleApp());

class FlutterTvosExampleApp extends StatelessWidget {
  const FlutterTvosExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_tvos Example',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        focusColor: Colors.blueAccent,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_tvos')),
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(child: PlatformInfoScreen()),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Focus grid — use arrow keys or Siri Remote swipes',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _FocusGrid()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: List.generate(16, (index) => _FocusCard(index: index)),
    );
  }
}

class _FocusCard extends StatefulWidget {
  const _FocusCard({required this.index});
  final int index;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  int _clicks = 0;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.index == 0,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => setState(() => _clicks++),
        ),
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasPrimaryFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: focused ? Colors.blueAccent : Colors.blueGrey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.index == 0
                  ? 'Select to click\n($_clicks clicks)'
                  : 'Tile ${widget.index}\n($_clicks clicks)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}

class PlatformInfoScreen extends StatelessWidget {
  const PlatformInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoTile(label: 'Is tvOS', value: '${TvOSInfo.isTvOS}'),
        _InfoTile(label: 'tvOS Version', value: TvOSInfo.tvOSVersion),
        _InfoTile(label: 'Device Model', value: TvOSInfo.deviceModel),
        _InfoTile(label: 'Machine ID', value: TvOSInfo.machineId),
        _InfoTile(label: 'Is Simulator', value: '${TvOSInfo.isSimulator}'),
        _InfoTile(label: 'Supports 4K', value: '${TvOSInfo.supports4K}'),
        _InfoTile(label: 'Supports HDR', value: '${TvOSInfo.supportsHDR}'),
        _InfoTile(label: 'Display', value: TvOSInfo.displayResolution),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
