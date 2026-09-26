import 'package:flutter/material.dart';

import '../application/club_controller.dart';
import '../domain/event_rules.dart';
import '../domain/models.dart';
import 'leaderboard_page.dart';
import 'localization.dart';

/// Displays event browsing, detail, and rankings within the Events destination.
/// The shell owns selection so event details share the app's back history.
class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    required this.controller,
    required this.selectedEventId,
    required this.onProfile,
    required this.onBack,
    required this.onOpenEvent,
    required this.onChangeEvent,
    required this.onMissingEvent,
  });

  final ClubController controller;
  final String? selectedEventId;
  final VoidCallback onProfile;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenEvent;
  final ValueChanged<String> onChangeEvent;
  final ValueChanged<String> onMissingEvent;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  String? _pendingMissingEventCheck;

  ClubEvent? _selectedEvent(ClubSnapshot snapshot) {
    final id = widget.selectedEventId;
    if (id == null) return null;
    return snapshot.events.where((event) => event.id == id).firstOrNull;
  }

  void _scheduleMissingEventRecovery(String eventId) {
    if (_pendingMissingEventCheck == eventId) return;
    _pendingMissingEventCheck = eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pendingMissingEventCheck == eventId) {
        _pendingMissingEventCheck = null;
      }
      // AnimatedSwitcher keeps outgoing pages mounted. Confirm this is still
      // the selected, missing event before asking the shell to recover it.
      if (widget.selectedEventId != eventId ||
          widget.controller.snapshot.events.any(
            (event) => event.id == eventId,
          )) {
        return;
      }
      widget.onMissingEvent(eventId);
    });
  }

  Future<void> _editEvent(BuildContext context, {ClubEvent? event}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EventEditorSheet(controller: widget.controller, event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final events = [...snapshot.events]
      ..sort((a, b) {
        final starts = a.startsAt.compareTo(b.startsAt);
        if (starts != 0) return starts;
        return a.id.compareTo(b.id);
      });
    final selectedEventId = widget.selectedEventId;
    final selected = _selectedEvent(snapshot);
    if (selectedEventId != null && selected == null) {
      _scheduleMissingEventRecovery(selectedEventId);
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: selected == null
              ? _EventListView(
                  controller: widget.controller,
                  events: events,
                  onProfile: widget.onProfile,
                  onEvent: (event) => widget.onOpenEvent(event.id),
                  onCreate: widget.controller.isAdmin
                      ? () => _editEvent(context)
                      : null,
                )
              : _EventDetailView(
                  snapshot: snapshot,
                  events: events,
                  event: selected,
                  isAdmin: widget.controller.isAdmin,
                  onBack: widget.onBack,
                  onEventChanged: (event) => widget.onChangeEvent(event.id),
                  onEdit: () => _editEvent(context, event: selected),
                ),
        ),
      ),
    );
  }
}

class _EventListView extends StatelessWidget {
  const _EventListView({
    required this.controller,
    required this.events,
    required this.onProfile,
    required this.onEvent,
    required this.onCreate,
  });

  final ClubController controller;
  final List<ClubEvent> events;
  final VoidCallback onProfile;
  final ValueChanged<ClubEvent> onEvent;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _EventsHeader(
          title: strings.text('活动', 'Events'),
          onProfile: onProfile,
        ),
        if (onCreate != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('create-event'),
            onPressed: controller.busy ? null : onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(strings.text('创建活动', 'Create event')),
          ),
        ],
        const SizedBox(height: 18),
        if (events.isEmpty)
          _EventEmptyState(
            title: strings.text('还没有活动', 'No events yet'),
            body: strings.text(
              '活动创建后会出现在这里。',
              'Events appear here after they are created.',
            ),
          )
        else
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventCard(
                event: event,
                snapshot: controller.snapshot,
                onOpen: () => onEvent(event),
              ),
            ),
      ],
    );
  }
}

class _EventsHeader extends StatelessWidget {
  const _EventsHeader({required this.title, required this.onProfile});

  final String title;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
      Semantics(
        button: true,
        label: context.t('打开个人设置', 'Open profile settings'),
        child: IconButton(
          key: const ValueKey('open-profile'),
          onPressed: onProfile,
          tooltip: context.t('个人设置', 'Profile settings'),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ),
    ],
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.snapshot,
    required this.onOpen,
  });

  final ClubEvent event;
  final ClubSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = _eventStatus(context, event, DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('event-card-${event.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _EventStatus(status: status),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                _eventDateRange(event),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  for (final roomId in event.roomIds)
                    Chip(
                      avatar: const Icon(
                        Icons.table_restaurant_outlined,
                        size: 15,
                      ),
                      label: Text(snapshot.roomName(roomId)),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('event-ranking-${event.id}'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.leaderboard_outlined, size: 18),
                  label: Text(context.t('查看活动排名', 'View event ranking')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventDetailView extends StatelessWidget {
  const _EventDetailView({
    required this.snapshot,
    required this.events,
    required this.event,
    required this.isAdmin,
    required this.onBack,
    required this.onEventChanged,
    required this.onEdit,
  });

  final ClubSnapshot snapshot;
  final List<ClubEvent> events;
  final ClubEvent event;
  final bool isAdmin;
  final VoidCallback onBack;
  final ValueChanged<ClubEvent> onEventChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: ValueKey('event-detail-${event.id}'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('event-detail-back'),
              onPressed: onBack,
              tooltip: strings.text('返回', 'Back'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                event.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (isAdmin)
              IconButton(
                key: const ValueKey('edit-event'),
                onPressed: onEdit,
                tooltip: strings.text('编辑活动', 'Edit event'),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _EventStatus(status: _eventStatus(context, event, DateTime.now())),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _eventDateRange(event),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('活动说明', 'Description'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  event.description.isEmpty
                      ? strings.text('暂无说明', 'No description')
                      : event.description,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                Text(
                  strings.text('时间（本地）', 'Time (local)'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(_eventDateRange(event)),
                const SizedBox(height: 14),
                Text(
                  strings.text('房间', 'Rooms'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final roomId in event.roomIds)
                      Chip(
                        avatar: const Icon(
                          Icons.table_restaurant_outlined,
                          size: 15,
                        ),
                        label: Text(snapshot.roomName(roomId)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          strings.text('活动排名', 'Event ranking'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          key: const ValueKey('event-ranking-selector'),
          initialValue: event.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.text('选择活动', 'Choose event'),
            prefixIcon: const Icon(Icons.swap_vert_rounded),
          ),
          items: [
            for (final item in events)
              DropdownMenuItem<String>(
                value: item.id,
                child: Text(item.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            final next = events.where((item) => item.id == id).firstOrNull;
            if (next != null) onEventChanged(next);
          },
        ),
        const SizedBox(height: 12),
        EventLeaderboard(snapshot: snapshot, event: event),
      ],
    );
  }
}

class _EventStatus extends StatelessWidget {
  const _EventStatus({required this.status});

  final _EventStatusValue status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = status == _EventStatusValue.current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        switch (status) {
          _EventStatusValue.upcoming => context.t('即将开始', 'Upcoming'),
          _EventStatusValue.current => context.t('进行中', 'Live'),
          _EventStatusValue.ended => context.t('已结束', 'Ended'),
        },
        style: TextStyle(
          color: active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _EventStatusValue { upcoming, current, ended }

_EventStatusValue _eventStatus(
  BuildContext context,
  ClubEvent event,
  DateTime now,
) {
  if (now.isBefore(event.startsAt)) return _EventStatusValue.upcoming;
  if (event.isActiveAt(now)) return _EventStatusValue.current;
  return _EventStatusValue.ended;
}

String _eventDateRange(ClubEvent event) =>
    '${_localDate(event.startsAt)} – ${_localDate(event.endsAt)}';

String _localDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day  $hour:$minute';
}

class _EventEmptyState extends StatelessWidget {
  const _EventEmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      child: Column(
        children: [
          Icon(
            Icons.event_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _EventEditorSheet extends StatefulWidget {
  const _EventEditorSheet({required this.controller, this.event});

  final ClubController controller;
  final ClubEvent? event;

  @override
  State<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<_EventEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _startsAt;
  late final TextEditingController _endsAt;
  DateTime? _originalStartsAt;
  DateTime? _originalEndsAt;
  String? _initialStartsAtText;
  String? _initialEndsAtText;
  late Set<String> _roomIds;
  int? _expectedVersion;
  String? _validationError;
  bool _safeRetryReady = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _name = TextEditingController(text: event?.name ?? '');
    _description = TextEditingController(text: event?.description ?? '');
    _startsAt = TextEditingController(
      text: event == null ? _initialDate(1) : _localDate(event.startsAt),
    );
    _endsAt = TextEditingController(
      text: event == null ? _initialDate(2) : _localDate(event.endsAt),
    );
    _originalStartsAt = event?.startsAt;
    _originalEndsAt = event?.endsAt;
    _initialStartsAtText = _startsAt.text;
    _initialEndsAtText = _endsAt.text;
    _roomIds = {...?event?.roomIds};
    _expectedVersion = event?.version;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _startsAt.dispose();
    _endsAt.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(TextEditingController target) async {
    final current = _parseLocal(target.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted || time == null) return;
    target.text = _localDate(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    setState(() {});
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final starts = _readDateTime(
      _startsAt.text,
      original: _originalStartsAt,
      initialText: _initialStartsAtText,
    );
    final ends = _readDateTime(
      _endsAt.text,
      original: _originalEndsAt,
      initialText: _initialEndsAtText,
    );
    if (starts == null || ends == null) {
      setState(
        () => _validationError = context.t(
          '请输入有效的本地时间，格式为 YYYY/MM/DD HH:MM。',
          'Enter valid local times as YYYY/MM/DD HH:MM.',
        ),
      );
      return;
    }
    final draft = EventDraft(
      id: widget.event?.id,
      expectedVersion: _expectedVersion,
      name: _name.text,
      description: _description.text,
      startsAt: starts,
      endsAt: ends,
      roomIds: [..._roomIds],
    );
    try {
      if (draft.id == null) {
        validateEventDraft(draft, widget.controller.snapshot.rooms);
      } else {
        validateEventEdit(draft, widget.controller.snapshot.games);
      }
    } on ClubException catch (error) {
      setState(() => _validationError = error.message);
      return;
    }
    setState(() {
      _validationError = null;
      _safeRetryReady = false;
    });
    final saved = await widget.controller.saveEvent(draft);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else if (widget.controller.lastActionConflict) {
      setState(() => _safeRetryReady = true);
    }
  }

  void _refreshVersionForReview() {
    final id = widget.event?.id;
    if (id == null) return;
    final current = widget.controller.snapshot.events
        .where((event) => event.id == id)
        .firstOrNull;
    if (current == null) return;
    setState(() {
      _expectedVersion = current.version;
      _safeRetryReady = false;
      _validationError = context.t(
        '版本已刷新；请确认编辑内容后再次保存。',
        'The version was refreshed. Review your edits and save again.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => SingleChildScrollView(
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
                        color: palette.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.event == null
                        ? strings.text('创建活动', 'Create event')
                        : strings.text('编辑活动', 'Edit event'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    strings.text('日期和时间按本地时间填写。', 'Enter local date and time.'),
                    style: TextStyle(
                      color: palette.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const ValueKey('event-name-field'),
                    controller: _name,
                    enabled: !widget.controller.busy,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: strings.text('活动名称', 'Event name'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('event-description-field'),
                    controller: _description,
                    enabled: !widget.controller.busy,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: strings.text('活动说明', 'Description'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DateTimeField(
                    controller: _startsAt,
                    label: strings.text('开始时间（本地）', 'Start time (local)'),
                    enabled: !widget.controller.busy,
                    onPick: () => _pickDateTime(_startsAt),
                  ),
                  const SizedBox(height: 10),
                  _DateTimeField(
                    controller: _endsAt,
                    label: strings.text('结束时间（本地）', 'End time (local)'),
                    enabled: !widget.controller.busy,
                    onPick: () => _pickDateTime(_endsAt),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    strings.text('可用房间', 'Rooms'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  for (final room in widget.controller.snapshot.rooms)
                    CheckboxListTile(
                      key: ValueKey('event-room-${room.id}'),
                      value: _roomIds.contains(room.id),
                      enabled: !widget.controller.busy,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(room.name),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _roomIds.add(room.id);
                        } else {
                          _roomIds.remove(room.id);
                        }
                      }),
                    ),
                  if (_validationError != null ||
                      widget.controller.error != null) ...[
                    const SizedBox(height: 8),
                    _EditorMessage(
                      message: _validationError ?? widget.controller.error!,
                      error: true,
                    ),
                  ],
                  if (_safeRetryReady) ...[
                    const SizedBox(height: 7),
                    OutlinedButton.icon(
                      key: const ValueKey('event-refresh-version'),
                      onPressed: _refreshVersionForReview,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        strings.text('刷新版本后重试', 'Refresh version to retry'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const ValueKey('save-event'),
                    onPressed: widget.controller.busy ? null : _save,
                    child: Text(
                      widget.controller.busy
                          ? strings.text('保存中…', 'Saving…')
                          : strings.text('保存活动', 'Save event'),
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextButton(
                    key: const ValueKey('cancel-event-editor'),
                    onPressed: widget.controller.busy
                        ? null
                        : () => Navigator.pop(context),
                    child: Text(strings.text('取消', 'Cancel')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        onPressed: enabled ? onPick : null,
        tooltip: context.t('选择日期和时间', 'Choose date and time'),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
  );
}

class _EditorMessage extends StatelessWidget {
  const _EditorMessage({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Text(
      doraMessage(context, message),
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _initialDate(int dayOffset) =>
    _localDate(DateTime.now().add(Duration(days: dayOffset)));

DateTime? _readDateTime(
  String value, {
  required DateTime? original,
  required String? initialText,
}) {
  // The editor intentionally shows minute precision. Preserve the exact
  // stored instant when an existing field was left untouched, including its
  // seconds, so a metadata-only edit cannot move a linked game outside the
  // event window.
  if (original != null && initialText == value) return original;
  return _parseLocal(value);
}

DateTime? _parseLocal(String value) {
  final match = RegExp(
    r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})\s+(\d{1,2}):(\d{2})$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  try {
    final parsed = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
    if (parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!) ||
        parsed.hour != int.parse(match.group(4)!) ||
        parsed.minute != int.parse(match.group(5)!)) {
      return null;
    }
    return parsed;
  } on FormatException {
    return null;
  }
}
