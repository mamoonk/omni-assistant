import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';
import '../state/layout_provider.dart';

/// Creates a user-defined dashboard tab with an explicit device set.
class NewTabDialog extends ConsumerStatefulWidget {
  const NewTabDialog({super.key});

  @override
  ConsumerState<NewTabDialog> createState() => _NewTabDialogState();
}

class _NewTabDialogState extends ConsumerState<NewTabDialog> {
  final _nameCtrl = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);

    return AlertDialog(
      title: const Text('New tab'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tab name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final device in devices)
                    CheckboxListTile(
                      dense: true,
                      title: Text(device.name),
                      subtitle: Text(device.roomId),
                      value: _selected.contains(device.id),
                      onChanged: (v) => setState(() => v == true
                          ? _selected.add(device.id)
                          : _selected.remove(device.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty || _selected.isEmpty) return;
            await ref
                .read(layoutProvider.notifier)
                .addTab(name, _selected.toList());
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
