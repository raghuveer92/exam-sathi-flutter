import 'package:flutter/material.dart';

/// Manual sync trigger — delegates refresh logic to the parent screen.
class SyncRefreshButton extends StatefulWidget {
  const SyncRefreshButton({
    super.key,
    required this.onRefreshed,
    this.tooltip = 'Sync data',
  });

  final Future<void> Function() onRefreshed;
  final String tooltip;

  @override
  State<SyncRefreshButton> createState() => _SyncRefreshButtonState();
}

class _SyncRefreshButtonState extends State<SyncRefreshButton> {
  bool _syncing = false;

  Future<void> _run() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await widget.onRefreshed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data synced')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: _syncing ? null : _run,
      icon: _syncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
    );
  }
}
