import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pcverse_app/core/diagnostic_service.dart';
import 'package:pcverse_app/core/pcverse_brand_tokens.dart';
import 'package:pcverse_app/core/pcverse_page_routes.dart';
import 'package:pcverse_app/presentation/pages/pc_test_page.dart';

/// ورود به دو بخش اختصاصی اپ: تست PC و همگام LED.
class LabHubPage extends StatelessWidget {
  const LabHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PcverseBrand.bgDeep,
      appBar: AppBar(
        title: const Text('ابزارهای PC شما'),
        backgroundColor: PcverseBrand.bgDeep,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'هر بخش در اپ جداست — ابزارها و پکیج‌های لازم همراه اپ نصب می‌شوند.',
            style: TextStyle(color: Colors.white60, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _LabCard(
            title: 'تست حرفه‌ای کامپیوتر',
            subtitle: 'سلامت سخت‌افزار، گلوگاه، عملکرد بازی، پیشنهاد ارتقا و مشاور PCVerse',
            icon: Icons.biotech_outlined,
            accent: const Color(0xFF22D3EE),
            onTap: () {
              Navigator.push(
                context,
                pcverseMaterialRoute<void>(
                  name: PcverseRouteNames.pcTest,
                  builder: (_) => const PcTestPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _LabCard(
            title: 'همگام LED، فن و LCD',
            subtitle: 'نور RAM و کیس، سرعت فن، LCD پمپ — درایورها داخل اپ',
            icon: Icons.lightbulb_outline,
            accent: const Color(0xFFA78BFA),
            onTap: () {
              Navigator.push(
                context,
                pcverseMaterialRoute<void>(
                  name: PcverseRouteNames.rgbLab,
                  builder: (_) => const RgbLabPage(),
                ),
              );
            },
          ),
          if (!Platform.isWindows) ...[
            const SizedBox(height: 20),
            const Text(
              'این بخش‌ها برای اپ ویندوز روی PC شخصی طراحی شده‌اند.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

/// همگام LED، فن و LCD — صفحهٔ اختصاصی اپ.
class RgbLabPage extends StatefulWidget {
  const RgbLabPage({super.key});

  @override
  State<RgbLabPage> createState() => _RgbLabPageState();
}

class _RgbLabPageState extends State<RgbLabPage> {
  final _svc = DiagnosticService();
  final _agent = PcverseWindowsAgentClient();
  bool _loading = false;
  bool _agentOnline = false;
  Map<String, dynamic>? _scan;
  Map<String, dynamic>? _catalog;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final ok = await _agent.isAvailable();
    final cat = await _svc.fetchRgbCatalog();
    if (!mounted) return;
    setState(() {
      _agentOnline = ok;
      _catalog = cat;
    });
    if (ok) await _scanRgb();
  }

  Future<void> _scanRgb() async {
    setState(() => _loading = true);
    final data = await _agent.rgbScan();
    if (mounted) {
      setState(() {
        _scan = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = (_scan?['devices'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final effects = (_catalog?['effects'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Scaffold(
      backgroundColor: PcverseBrand.bgDeep,
      appBar: AppBar(
        title: const Text('همگام LED و فن'),
        backgroundColor: PcverseBrand.bgDeep,
        actions: [
          IconButton(
            tooltip: 'اسکن مجدد',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => unawaited(_scanRgb()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(),
          const SizedBox(height: 12),
          _statusCard(),
          const SizedBox(height: 16),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (!_loading && devices.isEmpty)
            const Text(
              'دستگاه RGB پیدا نشد. اپ هنگام نصب ابزارهای لازم را همراه دارد — پس از راه‌اندازی کامل اپ دوباره اسکن کنید.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
          ...devices.map(_deviceTile),
          if (effects.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('افکت‌های آماده', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: effects.take(12).map((e) {
                return Chip(
                  label: Text(e['label_fa']?.toString() ?? e['id']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.white10,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.35)),
        gradient: LinearGradient(colors: [const Color(0xFFA78BFA).withValues(alpha: 0.12), Colors.transparent]),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('همگام LED، فن و LCD کیس', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
            'نور RAM و کیس، سرعت فن و تصویر LCD پمپ — همه روی همین PC. فایل‌ها به سرور ارسال نمی‌شوند.',
            style: TextStyle(color: Colors.white70, height: 1.55, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    return Card(
      color: Colors.white10,
      child: ListTile(
        leading: Icon(
          _agentOnline ? Icons.check_circle : Icons.settings_suggest_outlined,
          color: _agentOnline ? const Color(0xFF22D3EE) : Colors.orange,
        ),
        title: Text(_agentOnline ? 'سرویس همگام‌سازی فعال' : 'در انتظار راه‌اندازی سرویس محلی'),
        subtitle: Text(
          _agentOnline
              ? 'اسکن USB/HID و کنترل zone از همین اپ'
              : 'اپ هنگام اجرا ابزارهای LED و فن را آماده می‌کند',
        ),
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final name = d['name_fa']?.toString() ?? d['name']?.toString() ?? 'دستگاه';
    final zones = (d['zones'] as List?)?.length ?? 0;
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name),
        subtitle: Text('$zones zone · ${d['vendor'] ?? ''}', style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.tune, size: 18),
      ),
    );
  }
}
