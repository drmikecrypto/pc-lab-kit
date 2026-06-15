import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pcverse_app/core/diagnostic_service.dart';
import 'package:pcverse_app/core/pcverse_app_config.dart';
import 'package:pcverse_app/core/pcverse_brand_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// تست حرفه‌ای PC — صفحهٔ اختصاصی اپ (سنسور، گلوگاه، بازی، ارتقا).
class PcTestPage extends StatefulWidget {
  const PcTestPage({super.key, this.focusImportOnOpen = false});

  /// بعد از ورود، انتخاب فایل HWiNFO / CapFrameX / CPU-Z باز می‌شود (مثلاً از کارت SIS خانه).
  final bool focusImportOnOpen;

  @override
  State<PcTestPage> createState() => _PcTestPageState();
}

class _PcTestPageState extends State<PcTestPage> {
  final _svc = DiagnosticService();
  final _probe = SystemProbeService();
  bool _loading = false;
  bool _agentOnline = false;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _analysis;
  List<Map<String, dynamic>> _games = [];
  final Set<String> _selectedGames = {};
  String _importFormat = '';
  String? _importContent;
  Map<String, dynamic>? _live;
  List<Map<String, dynamic>> _history = [];
  int _gamesSearchSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadGames();
    _checkAgent();
    _loadLive();
    if (widget.focusImportOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _pickImport();
      });
    }
  }

  Future<void> _loadLive() async {
    final live = await _svc.fetchLive();
    final history = await _svc.fetchHistory();
    if (mounted) {
      setState(() {
        _live = live;
        _history = history;
      });
    }
  }

  Future<void> _checkAgent() async {
    final ok = await _svc.agent.isAvailable();
    if (mounted) setState(() => _agentOnline = ok);
  }

  Future<void> _loadGames([String q = '']) async {
    final seq = ++_gamesSearchSeq;
    final list = await _svc.searchGames(q);
    if (!mounted || seq != _gamesSearchSeq) return;
    setState(() => _games = list);
  }

  Future<void> _pickImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String? content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final head = content.length > 400 ? content.substring(0, 400).toLowerCase() : content.toLowerCase();
    final String format;
    if (ext == 'json') {
      format = 'capframex_json';
    } else if (ext == 'txt') {
      final name = (file.name).toLowerCase();
      final looksCpuZ = (name.contains('cpu') && name.contains('z')) || head.contains('cpu-z') || head.contains('cpuz');
      format = looksCpuZ ? 'cpuz_txt' : 'hwinfo_csv';
    } else {
      format = 'hwinfo_csv';
    }
    if (!mounted) return;
    setState(() {
      _importContent = content;
      _importFormat = format;
    });
  }

  Future<void> _runFullScan() async {
    setState(() {
      _loading = true;
      _analysis = null;
    });
    try {
      final probe = await _probe.collectProbe();
      final result = await _svc.submitFullReport(
        probe,
        gameIds: _selectedGames.toList(),
        importFormat: _importContent != null ? _importFormat : null,
        importContent: _importContent,
      );
      if (mounted) {
        setState(() {
          _report = probe;
          _analysis = result;
        });
        _loadLive();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PcverseBrand.bgDeep,
      appBar: AppBar(
        title: const Text('تست حرفه‌ای PC'),
        backgroundColor: PcverseBrand.bgDeep,
        actions: [
          IconButton(
            tooltip: 'بررسی مجدد سرویس محلی',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_checkAgent()),
          ),
          if (_agentOnline)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Center(child: Text('آماده ✓', style: TextStyle(color: Color(0xFF22D3EE), fontSize: 12))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(),
          if (_live != null) _livePanel(_live!),
          const SizedBox(height: 12),
          _agentCard(),
          const SizedBox(height: 20),
          _gamePicker(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickImport,
            icon: const Icon(Icons.upload_file),
            label: Text(_importContent != null ? 'ورودی: $_importFormat' : 'آپلود HWiNFO / CapFrameX'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _runFullScan,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.biotech),
            label: Text(_loading ? 'در حال اسکن…' : 'شروع تست کامل'),
            style: FilledButton.styleFrom(
              backgroundColor: PcverseBrand.primary,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          if (_report != null) ...[
            const SizedBox(height: 16),
            _probeSummary(_report!),
          ],
          if (_analysis != null) ...[
            const SizedBox(height: 24),
            _results(_analysis!),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            _historySection(),
          ],
        ],
      ),
    );
  }

  Widget _livePanel(Map<String, dynamic> live) {
    final stats = live['stats'] as Map<String, dynamic>? ?? {};
    final feed = (live['feed'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tools = live['tools_replaced'] ?? 13;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.25)),
        gradient: LinearGradient(colors: [const Color(0xFF22D3EE).withValues(alpha: 0.08), Colors.transparent]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('پایش زنده', style: TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('$tools اپ جایگزین', style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('امروز', '${stats['scans_today'] ?? 0}'),
              _statChip('۲۴h avg', '${stats['avg_health_24h'] ?? '—'}'),
              _statChip('کل', '${stats['total_scans'] ?? 0}'),
            ],
          ),
          if (feed.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: feed.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = feed[i];
                  return Chip(
                    label: Text('${f['score']} ${f['label']} · ${f['ago']}', style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.white10,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _historySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('تاریخچه تست‌ها', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ..._history.take(8).map((h) => Card(
              color: Colors.white10,
              child: ListTile(
                dense: true,
                leading: Text('${h['score']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF22D3EE))),
                title: Text('${h['gpu'] ?? h['cpu'] ?? ''} · ${h['mode']}'),
                subtitle: Text('${h['ago']} · ${h['bottleneck_fa'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final token = h['token']?.toString() ?? '';
                  if (token.isEmpty) return;
                  final data = await _svc.fetchReport(token);
                  final analysis = data['report']?['report']?['analysis'] ?? data['report'];
                  if (analysis is Map<String, dynamic> && mounted) {
                    setState(() => _analysis = analysis);
                  }
                },
              ),
            )),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [PcverseBrand.primary.withValues(alpha: 0.15), Colors.transparent],
        ),
        border: Border.all(color: PcverseBrand.primary.withValues(alpha: 0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تست حرفه‌ای کامپیوتر', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
            'سنسور واقعی، گلوگاه، عملکرد بازی و پیشنهاد ارتقا — ابزارهای لازم همراه اپ نصب می‌شوند.',
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _agentCard() {
    return Card(
      color: Colors.white10,
      child: ListTile(
        leading: Icon(_agentOnline ? Icons.check_circle : Icons.download, color: _agentOnline ? const Color(0xFF22D3EE) : Colors.orange),
        title: Text(_agentOnline ? 'سرویس تست فعال' : 'سرویس تست آماده نیست'),
        subtitle: Text(_agentOnline ? 'اسکن سخت‌افزار از همین اپ' : 'اپ هنگام اجرا ابزارهای لازم را راه‌اندازی می‌کند'),
        trailing: TextButton(
          onPressed: () async {
            final u = Uri.parse('${PcverseAppConfig.siteOrigin}/download/windows');
            if (await canLaunchUrl(u)) {
              await launchUrl(u, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('راهنما'),
        ),
      ),
    );
  }

  Widget _probeSummary(Map<String, dynamic> probe) {
    final cpu = probe['cpu'] as Map<String, dynamic>? ?? {};
    final gpu = probe['gpu'] as Map<String, dynamic>? ?? {};
    final ram = probe['ram'] as Map<String, dynamic>? ?? {};
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سخت‌افزار شما', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('CPU: ${cpu['model'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text('GPU: ${gpu['model'] ?? '—'} · ${gpu['vram_gb'] ?? '?'} GB VRAM', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text('RAM: ${ram['total_gb'] ?? '—'} GB', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _gamePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('بازی‌های مورد علاقه (تا ۲۰)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: 'جستجو در ۳۰۰ بازی…',
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: _loadGames,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _games.take(24).map((g) {
            final id = g['id']?.toString() ?? '';
            final sel = _selectedGames.contains(id);
            return FilterChip(
              label: Text(g['name']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
              selected: sel,
              onSelected: (v) {
                setState(() {
                  if (v && _selectedGames.length < 20) {
                    _selectedGames.add(id);
                  } else {
                    _selectedGames.remove(id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _results(Map<String, dynamic> data) {
    final score = data['health_score'] ?? '—';
    final grade = data['health_grade'] ?? '';
    final bn = data['bottleneck'] as Map<String, dynamic>?;
    final ai = data['ai_narrative_fa'] ?? (data['ai'] as Map?)?['summary_fa'] ?? '';
    final upgrades = (data['upgrade_suggestions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final gameSettings = (data['game_settings'] as List?) ?? [];
    final risks = (data['risks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final metrics = data['metrics'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('امتیاز: $score ($grade)', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF22D3EE))),
        if (bn != null) Text(bn['message_fa']?.toString() ?? '', style: const TextStyle(color: Colors.white70)),
        if (data['consultant'] is Map) _consultantCard(Map<String, dynamic>.from(data['consultant'] as Map)),
        if (upgrades.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            upgrades.any((u) => (u['reason_fa']?.toString().isNotEmpty ?? false)) ? 'پیشنهاد ارتقا از کاتالوگ' : 'پیشنهاد ارتقا',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          ...upgrades.map((u) {
                final catPath = _diagnosticCategoryBrowsePath(u);
                return ListTile(
                dense: true,
                title: Text(u['name_fa']?.toString() ?? ''),
                subtitle: Text(
                  [
                    if (u['is_partner'] == true) '⭐ همکار',
                    if ((u['why_fa'] ?? u['reason_fa'])?.toString().isNotEmpty == true) (u['why_fa'] ?? u['reason_fa']).toString(),
                  ].where((e) => e.isNotEmpty).join(' · '),
                ),
                trailing: catPath.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.storefront_outlined, size: 22),
                        tooltip: 'لیست این دسته در فروشگاه',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onPressed: () => _launchPcversePath(catPath),
                      )
                    : const Icon(Icons.open_in_new, size: 18),
                onTap: () async {
                  final path = u['url']?.toString() ?? '';
                  if (path.isEmpty) return;
                  await _launchPcversePath(path);
                },
              );
              }),
        ],
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (metrics['cpu_score'] != null) _metricChip('CPU', '${metrics['cpu_score']}'),
              if (metrics['gpu_score'] != null) _metricChip('GPU', '${metrics['gpu_score']}'),
              if (metrics['gpu_temp_max'] != null) _metricChip('GPU °C', '${metrics['gpu_temp_max']}'),
              if (metrics['cpu_temp_max'] != null) _metricChip('CPU °C', '${metrics['cpu_temp_max']}'),
              if (metrics['gpu_hotspot_max'] != null) _metricChip('Hotspot', '${metrics['gpu_hotspot_max']}°C'),
              if (metrics['frametime_p99_ms'] != null) _metricChip('FT p99', '${metrics['frametime_p99_ms']} ms'),
              if (metrics['lan_link_mbps'] != null) _metricChip('LAN', '${metrics['lan_link_mbps']} Mbps'),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final u = Uri.parse('${PcverseAppConfig.siteOrigin}/benchmarks');
                if (await canLaunchUrl(u)) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.thermostat, size: 16, color: Color(0xFF34D399)),
              label: const Text(
                'میانگین حرارتی جامعه (تالار بنچمارک)',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
          ),
        ],
        if (risks.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('ریسک‌ها', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          ...risks.map((r) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• ${r['message_fa']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              )),
        ],
        if (ai.toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(ai.toString(), style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
        if (gameSettings.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('تنظیمات پیشنهادی بازی', style: TextStyle(fontWeight: FontWeight.bold)),
          ...gameSettings.map((g) {
            final m = g as Map<String, dynamic>;
            final rec = m['recommended'] as Map<String, dynamic>? ?? {};
            return Card(
              color: Colors.white10,
              child: ListTile(
                title: Text(m['game_name']?.toString() ?? ''),
                subtitle: Text('${rec['resolution']} · ${rec['preset']} · ${rec['fps_target']} FPS'),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _consultantCard(Map<String, dynamic> c) {
    final headline = c['headline_fa']?.toString() ?? '';
    final honest = c['honest_assessment_fa']?.toString() ?? '';
    final horizons = (c['horizons'] as List?) ?? [];
    final catalog = c['catalog_angle_fa']?.toString() ?? '';
    final highlight = c['catalog_highlight_fa']?.toString() ?? '';
    final hasCatalogPicks = (c['catalog_picks'] as List?)?.isNotEmpty == true;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Card(
        color: const Color(0xFF1A1528),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x44A78BFA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology, size: 20, color: Colors.purple.shade200),
                  const SizedBox(width: 8),
                  const Text('مشاور PCVerse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              if (headline.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(headline, style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
              ],
              if (honest.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(honest, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75), height: 1.4)),
              ],
              if (horizons.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('افق زمانی', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF29F05))),
                ...horizons.take(3).map((h) {
                  final raw = h;
                  final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
                  final lb = m['label_fa']?.toString() ?? '';
                  final ad = m['advice_fa']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lb, style: const TextStyle(fontSize: 11, color: Color(0xFF22D3EE), fontWeight: FontWeight.w700)),
                        Text(ad, style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.35)),
                      ],
                    ),
                  );
                }),
              ],
              if (highlight.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(highlight, style: const TextStyle(fontSize: 11, color: Color(0xFF34D399), height: 1.35)),
              ],
              if (catalog.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(catalog, style: const TextStyle(fontSize: 11, color: Color(0xFF34D399), height: 1.35)),
              ],
              if (hasCatalogPicks) ...[
                const SizedBox(height: 6),
                Text(
                  'لیست قطعات با دلیل کوتاه در بخش «پیشنهاد ارتقا» پایین همین صفحه است.',
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45), height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _diagnosticCategoryBrowsePath(Map<String, dynamic> u) {
    final explicit = u['category_url']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit.startsWith('/') ? explicit : '/$explicit';
    }
    final slug = u['category_slug']?.toString().trim() ?? '';
    if (slug.isEmpty) return '';
    return '/parts/${Uri.encodeComponent(slug)}';
  }

  Future<void> _launchPcversePath(String path) async {
    if (path.isEmpty) return;
    final raw = Uri.parse('${PcverseAppConfig.siteOrigin}$path');
    if (await canLaunchUrl(raw)) {
      await launchUrl(raw, mode: LaunchMode.externalApplication);
    }
  }

  Widget _metricChip(String label, String value) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.white10,
    );
  }
}
