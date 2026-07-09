import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_providers.dart';
import '../state/layout_provider.dart';
import '../state/scenes_provider.dart';
import '../theme/ambient.dart';

/// Horizontal scene chips. Tap = activate; in edit mode: add / long-press delete.
class SceneBar extends ConsumerWidget {
  const SceneBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenes = ref.watch(scenesProvider);
    final editing = ref.watch(editModeProvider);
    if (scenes.isEmpty && !editing) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          for (final scene in scenes)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _RoutinePill(
                icon: Icons.play_arrow_rounded,
                label: scene.name,
                onLongPress: !editing
                    ? null
                    : () => _confirmDelete(context, ref, scene),
                onTap: () async {
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
          if (editing)
            _RoutinePill(
              icon: Icons.add,
              label: 'Scene',
              onTap: () => showDialog(
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

/// Echo-style frosted routine pill.
class _RoutinePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _RoutinePill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: Ambient.pill(selected: false),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Ambient.accent.withValues(alpha: 0.25),
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
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
