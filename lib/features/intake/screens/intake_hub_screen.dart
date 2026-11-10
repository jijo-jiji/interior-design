import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/config.dart';
import '../../../shared/labels.dart';
import '../../../shared/money.dart';
import '../../../shared/platform/api_client.dart';
import '../../../shared/project_status.dart';
import '../../../shared/sales_config.dart';
import '../../../shared/theme.dart';
import '../../catalog/catalog_repository.dart';
import '../../viewer/models/cpq_engine.dart';
import '../../viewer/utils/offline_store.dart';
import '../providers/consultation_provider.dart';

/// Home screen.
/// - New client: enter the client's name, then choose how to measure the
///   room (photo of the wall, floor plan, or sizes only).
/// - Clients: every saved design, quote and order, on this phone and from
///   the office, to search and reopen in 3D.
class IntakeHubScreen extends ConsumerStatefulWidget {
  const IntakeHubScreen({super.key});

  @override
  ConsumerState<IntakeHubScreen> createState() => _IntakeHubScreenState();
}

enum _Filter { all, draft, quote, deposit, unsent }

class _IntakeHubScreenState extends ConsumerState<IntakeHubScreen> {
  int _tab = 0; // 0 = New client, 1 = Clients
  bool _isPickingFile = false;

  bool _isLoading = false;
  List<Map<String, dynamic>> _projects = [];
  String _search = '';
  _Filter _filter = _Filter.all;
  int _waitingToSend = 0;

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  Future<void> _fetchProjects() async {
    setState(() => _isLoading = true);

    // Prices, sizes and tax come from the office; fetch the latest while the
    // list loads. A design already open keeps the version it started with.
    unawaited(CatalogRepository.sync());

    final local = await OfflineStore.getDrafts();
    final waiting = (await OfflineStore.pendingSync()).length;

    // Office server offline or unreachable: show what's on the device.
    var remote = <Map<String, dynamic>>[];
    final reply = await ApiClient.getJson(
        Uri.parse('${AppConfig.backendBaseUrl}/api/projects'));
    final list = reply != null && reply.ok ? reply.json : null;
    if (list is List) {
      remote = list.whereType<Map<String, dynamic>>().toList();
    }

    // Records on this phone first (newest work), then the office's.
    final merged = <Map<String, dynamic>>[
      ...local,
      ...remote.where((p) => !local.any((d) => d['quote_id'] == p['quote_id'])),
    ];

    if (mounted) {
      setState(() {
        _projects = merged;
        _waitingToSend = waiting;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendWaiting() async {
    final waiting = _waitingToSend;
    final count = await OfflineStore.syncQueue(AppConfig.quoteEndpoint);
    if (!mounted) return;
    final String message;
    if (count > 0) {
      message = 'Sent $count ${count == 1 ? 'quote' : 'quotes'} to the office.';
    } else if (waiting == 0) {
      message = 'Everything is already sent.';
    } else {
      message = "Couldn't reach the office. Try again when you're online.";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    _fetchProjects();
  }

  /// Asks who the design is for, then starts the chosen way of measuring.
  Future<void> _startNewClient(Future<void> Function() measure) async {
    final consultation = await showModalBottomSheet<Consultation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewClientSheet(),
    );
    if (consultation == null || !mounted) return;
    ref.read(consultationProvider.notifier).state = consultation;
    await measure();
    if (mounted) _fetchProjects();
  }

  Future<void> _openCamera() => context.push('/camera');

  Future<void> _openTemplate() => context.push('/template-room');

  Future<void> _pickFloorplanImage() async {
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);

    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file != null && mounted) {
        await context.push('/floorplan', extra: file.path);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open that image. Try another one."),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  Future<void> _openProject(Map<String, dynamic> project) async {
    final payload = {
      'wall': project['wall'] ??
          {
            'width_mm': 4000.0,
            'height_mm': 2700.0,
            'depth_mm': 150.0,
          },
      'obstacles': project['obstacles'] ?? [],
      if (_floorPlanOf(project) case final plan?) 'floor_plan': plan,
      if (project['capture'] case final Map<String, dynamic> capture)
        'capture': capture,
      if (project['keep_wall_photo'] case final bool keep) 'keep_wall_photo': keep,
      if (project['wall_photo_path'] case final String path)
        'wall_photo_path': path,
      'placed_cabinets': project['placed_cabinets'] ?? [],
      'style_archetype': project['style_archetype'] ?? 'japandi',
      'benchtop_material': project['benchtop_material'],
      'client_name': project['client_name'] ?? '',
      'client_phone': project['client_phone'] ?? '',
      'client_email': project['client_email'] ?? '',
      'deposit_paid': project['deposit_paid'] ?? 0.0,
      'quote_id': project['quote_id'] ?? '',
      'status': ProjectStatus.of(project).name,
    };
    await context.push('/viewer', extra: jsonEncode(payload));
    if (mounted) _fetchProjects();
  }

  bool _isUnsent(Map<String, dynamic> p) =>
      p['is_offline_draft'] == true &&
      ProjectStatus.of(p) != ProjectStatus.draft;

  bool _matchesFilter(Map<String, dynamic> p, _Filter filter) =>
      switch (filter) {
        _Filter.all => true,
        _Filter.draft => ProjectStatus.of(p) == ProjectStatus.draft,
        _Filter.quote => ProjectStatus.of(p) == ProjectStatus.quote,
        _Filter.deposit => ProjectStatus.of(p) == ProjectStatus.deposit,
        _Filter.unsent => _isUnsent(p),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: AppTheme.border, height: 1),
            _buildTabs(),
            Expanded(child: _tab == 0 ? _buildNewClient() : _buildClients()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final waiting = _waitingToSend > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SalesConfig.brandName,
                  style: context.textTheme.titleMedium
                      ?.copyWith(color: context.colors.onSurface),
                ),
                SizedBox(height: 2),
                Text(
                  SalesConfig.brandTagline,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _sendWaiting,
            style: TextButton.styleFrom(
              foregroundColor:
                  waiting ? AppTheme.textPrimary : AppTheme.success,
              minimumSize: const Size(48, 48),
            ),
            icon: Icon(
              waiting ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
              size: 18,
            ),
            label: Text(waiting ? '$_waitingToSend to send' : 'All sent'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    Widget tab(int index, String label) {
      final selected = _tab == index;
      return Expanded(
        child: InkWell(
          onTap: () {
            setState(() => _tab = index);
            if (index == 1) _fetchProjects();
          },
          borderRadius: BorderRadius.circular(9),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: context.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? context.colors.onPrimary
                      : context.colors.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          tab(0, 'New client'),
          tab(1,
              _projects.isEmpty ? 'Clients' : 'Clients (${_projects.length})'),
        ],
      ),
    );
  }

  /// The newest unfinished design on this phone, to pick up where the
  /// salesperson left off.
  Map<String, dynamic>? get _lastDraft {
    final drafts = _projects
        .where((p) =>
            ProjectStatus.of(p) == ProjectStatus.draft &&
            p['saved_at'] is String)
        .toList()
      ..sort((a, b) =>
          (b['saved_at'] as String).compareTo(a['saved_at'] as String));
    return drafts.isEmpty ? null : drafts.first;
  }

  Widget _buildNewClient() {
    final lastDraft = _lastDraft;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (lastDraft != null) ...[
          _ContinueCard(
            project: lastDraft,
            onTap: () => _openProject(lastDraft),
          ),
          const SizedBox(height: 20),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How will you measure the room?',
                style: context.textTheme.titleMedium
                    ?.copyWith(color: context.colors.onSurface),
              ),
              SizedBox(height: 4),
              Text(
                "You'll add the client's name first.",
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        _MeasureCard(
          title: 'Photo of the wall',
          description:
              'Take a photo: the wall is traced, then you check its size '
              'with a tape and add the windows and doors.',
          tag: 'Most accurate',
          icon: Icons.camera_alt_rounded,
          accentColor: AppTheme.accent,
          onTap: () => _startNewClient(_openCamera),
        ),
        const SizedBox(height: 12),
        _MeasureCard(
          title: 'Floor plan',
          description:
              'Use a floor plan image from WhatsApp or your gallery. The '
              "kitchen's sizes are read off it for you.",
          tag: 'From a developer plan',
          icon: Icons.architecture_rounded,
          accentColor: AppTheme.success,
          isLoading: _isPickingFile,
          onTap: () => _startNewClient(_pickFloorplanImage),
        ),
        const SizedBox(height: 12),
        _MeasureCard(
          title: 'Room size only',
          description:
              "Pick the room shape and type in the sizes. Best when there's no "
              'photo or plan.',
          tag: 'Fastest',
          icon: Icons.straighten_rounded,
          accentColor: AppTheme.accent,
          onTap: () => _startNewClient(_openTemplate),
        ),
      ],
    );
  }

  Widget _buildClients() {
    final q = _search.toLowerCase();
    final visible = _projects.where((p) {
      final name = (p['client_name'] as String? ?? '').toLowerCase();
      final id = (p['quote_id'] as String? ?? '').toLowerCase();
      return (name.contains(q) || id.contains(q)) && _matchesFilter(p, _filter);
    }).toList();
    int count(_Filter f) => _projects.where((p) => _matchesFilter(p, f)).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: context.textTheme.bodyLarge
                      ?.copyWith(color: context.colors.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search by client or quote number',
                    hintStyle: context.textTheme.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent),
                onPressed: _fetchProjects,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (f, label) in [
                (_Filter.all, 'All'),
                (_Filter.draft, 'Drafts'),
                (_Filter.quote, 'Quotes sent'),
                (_Filter.deposit, 'Deposit paid'),
                (_Filter.unsent, 'Waiting to send'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: '$label (${count(f)})',
                    isSelected: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                )
              : visible.isEmpty
                  ? _EmptyClients(hasAny: _projects.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ClientCard(
                        project: visible[i],
                        unsent: _isUnsent(visible[i]),
                        onTap: () => _openProject(visible[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── New client sheet ─────────────────────────────────────────────────────

class _NewClientSheet extends StatefulWidget {
  const _NewClientSheet();

  @override
  State<_NewClientSheet> createState() => _NewClientSheetState();
}

class _NewClientSheetState extends State<_NewClientSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _continue({bool skip = false}) {
    Navigator.pop(
      context,
      Consultation(
        quoteId: newQuoteId(),
        clientName: skip ? '' : _name.text.trim(),
        clientPhone: skip ? '' : _phone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _name.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New client',
                style: context.textTheme.titleMedium
                    ?.copyWith(color: context.colors.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'Their design is saved under this name as you work.',
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Client name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (hasName) _continue();
                },
                decoration: const InputDecoration(
                  labelText: 'Phone / WhatsApp (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                child: ElevatedButton(
                  onPressed: hasName ? _continue : null,
                  child: const Text('Continue'),
                ),
              ),
              TextButton(
                onPressed: () => _continue(skip: true),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────

class _MeasureCard extends StatelessWidget {
  final String title;
  final String description;
  final String tag;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isLoading;

  const _MeasureCard({
    required this.title,
    required this.description,
    required this.tag,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border, width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: accentColor,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleSmall
                          ?.copyWith(color: context.colors.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tag,
                      style: context.textTheme.labelMedium
                          ?.copyWith(color: accentColor),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Continue Puan Aminah's design · saved 10 min ago".
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.project, required this.onTap});

  final Map<String, dynamic> project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (project['client_name'] as String? ?? '').trim();
    final title =
        name.isEmpty ? 'Continue the last design' : "Continue $name's design";
    final saved = DateTime.tryParse(project['saved_at'] as String? ?? '');
    final subtitle =
        saved == null ? 'Draft' : 'Draft · saved ${timeAgoLabel(saved)}';

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      // The InkWell's own tap is hidden by excludeSemantics: give TalkBack
      // (and the browser's accessibility tree) the tap here.
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentDim,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border, width: 1.2),
          ),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: AppTheme.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleSmall
                          ?.copyWith(color: context.colors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final bool unsent;
  final VoidCallback onTap;

  const _ClientCard({
    required this.project,
    required this.unsent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = ProjectStatus.of(project);
    final name = project['client_name'] as String? ?? '';
    final total = (project['total_price'] as num? ?? 0).toDouble();
    final styleKey = project['style_archetype'] as String? ?? 'japandi';
    final cabinets = ((project['placed_cabinets'] as List?) ?? const [])
        .where((c) => c is! Map || c['kind'] != 'filler')
        .length;
    final statusColor = switch (status) {
      ProjectStatus.deposit => AppTheme.success,
      ProjectStatus.quote => AppTheme.textPrimary,
      ProjectStatus.draft => AppTheme.textSecondary,
    };

    Widget tag(String text, Color color, Color background) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: context.textTheme.labelSmall?.copyWith(color: color),
          ),
        );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? 'Unnamed client' : name,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall
                        ?.copyWith(color: context.colors.onSurface),
                  ),
                ),
                if (total > 0)
                  Text(
                    formatMoney(total),
                    style: context.textTheme.labelLarge
                        ?.copyWith(color: context.colors.onSurface),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${project['quote_id'] ?? ''}  ·  '
              '${CPQEngine.styleNames[styleKey] ?? styleKey}  ·  '
              '${cabinetCountLabel(cabinets)}',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tag(status.label, statusColor, AppTheme.surfaceRaised),
                if (unsent) ...[
                  const SizedBox(width: 6),
                  tag('Waiting to send', AppTheme.textPrimary,
                      AppTheme.accentTerracotta.withValues(alpha: 0.35)),
                ],
                const Spacer(),
                Text(
                  'Open',
                  style: context.textTheme.labelLarge
                      ?.copyWith(color: context.colors.primary),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.accent, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyClients extends StatelessWidget {
  final bool hasAny;
  const _EmptyClients({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded,
                size: 44, color: AppTheme.textSecondary),
            const SizedBox(height: 10),
            Text(
              hasAny
                  ? 'No clients match.'
                  : 'No clients yet. Start one from New client.',
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.accent : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? context.colors.onPrimary
                    : context.colors.onSurface),
          ),
        ),
      ),
    );
  }
}

/// A project's floor plan (for the 3D's Room and House views), with a
/// picture stored on the office server turned into a full address the 3D
/// page can load.
Map<String, dynamic>? _floorPlanOf(Map<String, dynamic> project) {
  final plan = project['floor_plan'];
  if (plan is! Map) return null;
  final out = Map<String, dynamic>.from(plan);
  final image = out['image'];
  if (image is String && image.startsWith('/')) {
    out['image'] = '${AppConfig.backendBaseUrl}$image';
  }
  return out;
}
