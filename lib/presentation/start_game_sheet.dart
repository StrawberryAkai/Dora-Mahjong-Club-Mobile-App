import 'package:flutter/material.dart';

import '../application/club_controller.dart';
import '../domain/event_rules.dart';
import '../domain/models.dart';
import 'localization.dart';

/// A selected event id is nullable because casual games are deliberately
/// unlinked. [cancelled] keeps that choice distinct from dismissing the sheet.
class GameStartSelection {
  const GameStartSelection({this.eventId, this.cancelled = false});

  const GameStartSelection.casual() : this();
  const GameStartSelection.cancelled() : this(cancelled: true);

  final String? eventId;
  final bool cancelled;
}

Future<GameStartSelection> showGameStartSheet({
  required BuildContext context,
  required ClubController controller,
  required ClubRoom room,
}) async {
  final selection = await showModalBottomSheet<GameStartSelection>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GameStartSheet(controller: controller, room: room),
  );
  return selection ?? const GameStartSelection.cancelled();
}

class _GameStartSheet extends StatelessWidget {
  const _GameStartSheet({required this.controller, required this.room});

  final ClubController controller;
  final ClubRoom room;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final events = eligibleEvents(controller.snapshot, room.id, DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  strings.text('开始对局', 'Start game'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  strings.text(
                    '选择活动会把这场对局永久关联到活动；也可以直接开始休闲对局。',
                    'Link this game to an event, or start an unlinked casual game.',
                  ),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 17),
                OutlinedButton.icon(
                  key: const ValueKey('start-casual-game'),
                  onPressed: () =>
                      Navigator.pop(context, const GameStartSelection.casual()),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(strings.text('休闲对局', 'Casual game')),
                ),
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    strings.text('当前活动', 'Active events'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 7),
                  for (final event in events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          key: ValueKey('start-event-${event.id}'),
                          onTap: () => Navigator.pop(
                            context,
                            GameStartSelection(eventId: event.id),
                          ),
                          leading: const Icon(Icons.event_available_outlined),
                          title: Text(event.name),
                          subtitle: Text(_startSheetDate(context, event)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      strings.text(
                        '当前房间没有进行中的活动。',
                        'There are no active events for this room.',
                      ),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  key: const ValueKey('cancel-start-game'),
                  onPressed: () => Navigator.pop(
                    context,
                    const GameStartSelection.cancelled(),
                  ),
                  child: Text(strings.text('取消', 'Cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _startSheetDate(BuildContext context, ClubEvent event) {
  final local = event.endsAt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return context.t(
    '截止 ${local.year}/$month/$day $hour:$minute',
    'Until ${local.year}/$month/$day $hour:$minute',
  );
}
