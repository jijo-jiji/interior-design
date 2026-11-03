import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/theme.dart';
import '../../../shared/config.dart';
import '../../viewer/utils/offline_store.dart';

/// Root consultation launcher & CRM Pipeline Hub:
/// 1. Tab 1 (Start Consultation): Camera wall capture, 2D blueprint calibration, 10s template room.
/// 2. Tab 2 (Pipeline & History): Search, inspect, and reopen client quotes & offline drafts in 3D.
class IntakeHubScreen extends StatefulWidget {
  const IntakeHubScreen({super.key});

  @override
  State<IntakeHubScreen> createState() => _IntakeHubScreenState();
}

class _IntakeHubScreenState extends State<IntakeHubScreen> {
  int _selectedTabIndex = 0; // 0 = New Consultation, 1 = Pipeline & History
  bool _isPickingFile = false;

  // Pipeline state
  bool _isLoadingProjects = false;
  List<Map<String, dynamic>> _projects = [];
  String _searchQuery = '';
  String _pipelineFilter = 'all'; // 'all', 'locked', 'estimates', 'offline'
  int _offlineDraftCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchPipeline();
  }

  Future<void> _fetchPipeline() async {
    setState(() => _isLoadingProjects = true);

    final drafts = await OfflineStore.getDrafts();
    _offlineDraftCount = drafts.length;

    List<Map<String, dynamic>> remoteProjects = [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client
          .getUrl(Uri.parse('${AppConfig.backendBaseUrl}/api/projects'));
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;
        remoteProjects = list.cast<Map<String, dynamic>>();
      }
      client.close();
    } catch (_) {
      // Backend offline or unreachable
    }

    // Merge offline drafts at top, followed by cloud projects
    final merged = <Map<String, dynamic>>[
      ...drafts,
      ...remoteProjects
          .where((p) => !drafts.any((d) => d['quote_id'] == p['quote_id'])),
    ];

    if (mounted) {
      setState(() {
        _projects = merged;
        _isLoadingProjects = false;
      });
    }
  }

  Future<void> _syncOfflineDrafts() async {
    final count = await OfflineStore.syncQueue(AppConfig.quoteEndpoint);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? 'Successfully synced $count offline quote(s) with studio cloud!'
            : 'No pending offline quotes or studio unreachable.'),
        backgroundColor: count > 0 ? const Color(0xFF16A34A) : AppTheme.accent,
      ),
    );
    _fetchPipeline();
  }

  Future<void> _pickFloorplanImage() async {
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (file != null && mounted) {
        context.push('/floorplan-calibrate', extra: file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open floor plan: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  void _openProjectInViewer(Map<String, dynamic> project) {
    // Construct payload ensuring wall and placed cabinets are passed
    final payload = {
      'wall': project['wall'] ??
          {
            'width_mm': 4000.0,
            'height_mm': 2700.0,
            'depth_mm': 150.0,
          },
      'obstacles': project['obstacles'] ?? [],
      'placed_cabinets': project['placed_cabinets'] ?? [],
      'style_archetype': project['style_archetype'] ?? 'japandi',
      'client_name': project['client_name'] ?? 'Client',
      'client_phone': project['client_phone'] ?? '',
      'client_email': project['client_email'] ?? '',
      'deposit_paid': project['deposit_paid'] ?? 0.0,
      'quote_id': project['quote_id'] ?? '',
    };

    context.push('/viewer', extra: jsonEncode(payload));
  }

  @override
  Widget build(BuildContext context) {
    final filteredProjects = _projects.where((p) {
      final q = _searchQuery.toLowerCase();
      final name = (p['client_name'] as String? ?? '').toLowerCase();
      final qid = (p['quote_id'] as String? ?? '').toLowerCase();
      final style = (p['style_archetype'] as String? ?? '').toLowerCase();
      final matchesQuery =
          name.contains(q) || qid.contains(q) || style.contains(q);
      if (!matchesQuery) return false;

      final isOffline = p['is_offline_draft'] == true;
      final depositPaid = (p['deposit_paid'] as num? ?? 0.0) > 0;

      if (_pipelineFilter == 'locked') return depositPaid;
      if (_pipelineFilter == 'estimates') return !depositPaid && !isOffline;
      if (_pipelineFilter == 'offline') return isOffline;
      return true;
    }).toList();

    final lockedCount =
        _projects.where((p) => (p['deposit_paid'] as num? ?? 0.0) > 0).length;
    final estimateCount = _projects
        .where((p) =>
            (p['deposit_paid'] as num? ?? 0.0) == 0 &&
            p['is_offline_draft'] != true)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header Bar ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.view_in_ar_rounded,
                              color: AppTheme.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'STATIC TRACE',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'In-Person Interior Design Sales Closer',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  // Offline status / sync pill
                  InkWell(
                    onTap: _syncOfflineDrafts,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _offlineDraftCount > 0
                            ? AppTheme.accentTerracotta.withOpacity(0.25)
                            : AppTheme.successDim,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _offlineDraftCount > 0
                              ? AppTheme.accentTaupe
                              : AppTheme.success.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _offlineDraftCount > 0
                                ? Icons.cloud_upload_rounded
                                : Icons.wifi_off_rounded,
                            size: 13,
                            color: _offlineDraftCount > 0
                                ? AppTheme.textPrimary
                                : AppTheme.success,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _offlineDraftCount > 0
                                ? '$_offlineDraftCount Offline'
                                : 'Offline Ready',
                            style: TextStyle(
                              color: _offlineDraftCount > 0
                                  ? AppTheme.textPrimary
                                  : AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.border, height: 1),

            // ── Primary Tab Bar (New Consultation vs Pipeline) ───────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTabIndex == 0
                              ? AppTheme.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(
                          child: Text(
                            'Start Consultation',
                            style: TextStyle(
                              color: _selectedTabIndex == 0
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedTabIndex = 1);
                        _fetchPipeline();
                      },
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTabIndex == 1
                              ? AppTheme.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Pipeline & History',
                              style: TextStyle(
                                color: _selectedTabIndex == 1
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_projects.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _selectedTabIndex == 1
                                      ? Colors.white.withOpacity(0.25)
                                      : AppTheme.surfaceElevated,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_projects.length}',
                                  style: TextStyle(
                                    color: _selectedTabIndex == 1
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab 1: Start Consultation ────────────────────────────────
            if (_selectedTabIndex == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Room Intake Mode',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose how to bring the client room into 3D:',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // ── Luxury Hero Consultation Launcher Card ───────────
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEEE4E1), Color(0xFFE7D8C9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.border, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        color: AppTheme.accent, size: 13),
                                    SizedBox(width: 4),
                                    Text(
                                      'ATELIER ACCELERATOR',
                                      style: TextStyle(
                                        color: AppTheme.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Avg Close: 4m 12s',
                                style: TextStyle(
                                  color:
                                      AppTheme.textSecondary.withOpacity(0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Ready for On-Site Co-Design',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'From live room measurement to itemized BOQ and signed customer deposit in under 5 minutes.',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withOpacity(0.9),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    _ConsultationCard(
                      title: 'Camera Wall Trace',
                      subtitle:
                          'Point camera at client wall, freeze perspective & drag door/window cutouts on-site.',
                      badge: 'MOST ACCURATE ON-SITE',
                      badgeColor: AppTheme.accentTaupe,
                      icon: Icons.camera_alt_rounded,
                      accentColor: AppTheme.accent,
                      onTap: () => context.push('/camera'),
                    ),
                    const SizedBox(height: 14),
                    _ConsultationCard(
                      title: '2D Floor Plan Blueprint',
                      subtitle:
                          'Import developer PDF or photo from WhatsApp/Gallery. Calibrate scale with 2 points.',
                      badge: 'DEVELOPER PLANS & BROCHURES',
                      badgeColor: AppTheme.success,
                      icon: Icons.architecture_rounded,
                      accentColor: AppTheme.success,
                      isLoading: _isPickingFile,
                      onTap: _pickFloorplanImage,
                    ),
                    const SizedBox(height: 14),
                    _ConsultationCard(
                      title: '10-Second Quick Template',
                      subtitle:
                          'Instant Single Wall, L-Shape, or Galley room with dimension sliders for fast showroom pitches.',
                      badge: 'FASTEST (NO PLANS NEEDED)',
                      badgeColor: AppTheme.accentTaupe,
                      icon: Icons.bolt_rounded,
                      accentColor: AppTheme.accentTaupe,
                      onTap: () => context.push('/template-room'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ]

            // ── Tab 2: Consultation Pipeline & History ───────────────────
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Search client, quote ID, or style...',
                            hintStyle: TextStyle(
                                color: AppTheme.textTertiary, fontSize: 12),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 18, color: AppTheme.textSecondary),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Refresh Pipeline',
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppTheme.accent),
                      onPressed: _fetchPipeline,
                    ),
                  ],
                ),
              ),

              // Pipeline status filter chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All (${_projects.length})',
                        isSelected: _pipelineFilter == 'all',
                        onTap: () => setState(() => _pipelineFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Priority Locked ($lockedCount)',
                        isSelected: _pipelineFilter == 'locked',
                        accentColor: AppTheme.success,
                        onTap: () => setState(() => _pipelineFilter = 'locked'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Estimates ($estimateCount)',
                        isSelected: _pipelineFilter == 'estimates',
                        accentColor: AppTheme.accent,
                        onTap: () =>
                            setState(() => _pipelineFilter = 'estimates'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Offline Drafts ($_offlineDraftCount)',
                        isSelected: _pipelineFilter == 'offline',
                        accentColor: AppTheme.accentTaupe,
                        onTap: () =>
                            setState(() => _pipelineFilter = 'offline'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingProjects
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent))
                    : filteredProjects.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_rounded,
                                    size: 48,
                                    color:
                                        AppTheme.textTertiary.withOpacity(0.5)),
                                const SizedBox(height: 10),
                                const Text(
                                  'No matching consultations found.',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: filteredProjects.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final p = filteredProjects[idx];
                              final isOffline = p['is_offline_draft'] == true;
                              final deposit =
                                  (p['deposit_paid'] as num? ?? 0) > 0;
                              final style =
                                  (p['style_archetype'] as String? ?? 'japandi')
                                      .toUpperCase();
                              final totalPrice =
                                  (p['total_price'] as num? ?? 0).toDouble();

                              return InkWell(
                                onTap: () => _openProjectInViewer(p),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isOffline
                                          ? AppTheme.accentTaupe
                                          : AppTheme.border,
                                      width: 1.1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2C2724)
                                            .withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p['client_name'] as String? ??
                                                  'Client Consultation',
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '\$${totalPrice.toStringAsFixed(0)} AUD',
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            p['quote_id'] as String? ?? '',
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 11),
                                          ),
                                          const Spacer(),
                                          // Style tag
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceRaised,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: AppTheme.border),
                                            ),
                                            child: Text(
                                              style,
                                              style: const TextStyle(
                                                  color: AppTheme.accentTaupe,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // Status tag
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isOffline
                                                  ? AppTheme.accentTerracotta
                                                      .withOpacity(0.3)
                                                  : (deposit
                                                      ? AppTheme.successDim
                                                      : AppTheme.surfaceRaised),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isOffline
                                                  ? 'OFFLINE DRAFT'
                                                  : (deposit
                                                      ? 'PRIORITY LOCKED'
                                                      : 'ESTIMATE'),
                                              style: TextStyle(
                                                color: isOffline
                                                    ? AppTheme.textPrimary
                                                    : (deposit
                                                        ? AppTheme.success
                                                        : AppTheme
                                                            .textSecondary),
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${(p['placed_cabinets'] as List?)?.length ?? 0} modules placed',
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 11),
                                          ),
                                          const Row(
                                            children: [
                                              Text(
                                                'Open in 3D',
                                                style: TextStyle(
                                                    color: AppTheme.accent,
                                                    fontSize: 11.5,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              SizedBox(width: 4),
                                              Icon(Icons.arrow_forward_rounded,
                                                  color: AppTheme.accent,
                                                  size: 13),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],

            // ── Footer ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceRaised,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Three.js Local Engine Loaded',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  Text(
                    'v2.0.0 • Sales Closer Hub',
                    style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.7),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isLoading;

  const _ConsultationCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2C2724).withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: badgeColor.withOpacity(0.35), width: 0.8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: accentColor, strokeWidth: 2),
                        )
                      : Icon(icon, color: accentColor, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.textSecondary.withOpacity(0.85),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Launch Mode',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
  final Color accentColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.accentColor = AppTheme.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : AppTheme.border,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
