import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';
import '../state/layout_provider.dart';
import '../state/scenes_provider.dart';

/// Horizontal scene chips. Tap = activate; in edit mode: add / long-press delete.
class SceneBar extends ConsumerWidget {
  const SceneBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenes = ref.watch(scenesProvider);
    final editing = ref.watch(editModeProvider);
    if (scenes.isEmpty && !editing) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final scene in scenes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: !editing
                    ? null
                    : () => _confirmDelete(context, ref, scene),
                child: ActionChip(
                  avatar: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text(scene.name),
                  onPressed: () async {
                    await ref.read(scenesProvider.notifier).activate(scene);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Scene "${scene.name}" activated'),
                        duration: const Duration(seconds: 1),
                      ));
                    }
                  },
                ),
              ),
            ),
          if (editing)
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Scene'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const NewSceneDialog(),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Scene scene) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete scene "${scene.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(scenesProvider.notifier).remove(scene.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Name + device picker; captures the devices' current state as the scene.
class NewSceneDialog extends ConsumerStatefulWidget {
  const NewSceneDialog({super.key});

  @override
  ConsumerState<NewSceneDialog> createState() => _NewSceneDialogState();
}

class _NewSceneDialogState extends ConsumerState<NewSceneDialog> {
  final _nameCtrl = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // only devices with a capturable capability make sense in a scene
    final devices = ref
        .watch(devicesProvider)
        .where((d) => d.capabilities.any((c) => sceneValueFor(c) != null))
        .toList();

    return AlertDialog(
      title: const Text('New scene'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Devices to capture (current state becomes the scene):',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
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
                .read(scenesProvider.notifier)
                .createFromCurrentState(name, _selected);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
