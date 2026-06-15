import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pcverse_app/core/pcverse_app_config.dart';

/// Fetches hardware JSON from local PCVerse Probe agent (Windows).
class PcverseWindowsAgentClient {
  static String get _agentBase =>
      PcverseAppConfig.windowsAgentBase.replaceAll(RegExp(r'/+$'), '');

  Future<bool> isAvailable() async {
    if (!Platform.isWindows) return false;
    try {
      final res = await http
          .get(Uri.parse('$_agentBase/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchProbe() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await http
          .get(Uri.parse('$_agentBase/probe'))
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> rgbScan() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await http
          .get(Uri.parse('$_agentBase/rgb/scan'))
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// Collects device/system probe data for full diagnostic report.
class SystemProbeService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Battery _battery = Battery();
  final PcverseWindowsAgentClient _agent = PcverseWindowsAgentClient();

  Future<Map<String, dynamic>> collectProbe() async {
    if (Platform.isWindows) {
      final agentData = await _agent.fetchProbe();
      if (agentData != null && (agentData['probe_version'] ?? 0) >= 2) {
        return agentData;
      }
    }

    final device = await _deviceSection();
    final network = await _networkSection();
    Map<String, dynamic> battery = {};
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      battery = {
        'level_percent': level,
        'state': state.name,
        'health_percent': level > 0 ? level : null,
      };
    } catch (_) {}

    return {
      'device': device,
      'cpu': await _cpuSection(device),
      'gpu': await _gpuSection(device),
      'ram': await _ramSection(device),
      'storage': {'note': Platform.isWindows ? 'Install PCVerse Probe for SMART data' : 'Limited on mobile'},
      'motherboard': {},
      'psu': {},
      'network': network,
      'battery': battery,
      'sensors': {},
      'gaming': {},
      'peripherals': [],
      'collected_at': DateTime.now().toIso8601String(),
      'probe_version': 1,
    };
  }

  Future<Map<String, dynamic>> _deviceSection() async {
    if (Platform.isAndroid) {
      final a = await _deviceInfo.androidInfo;
      return {
        'form_factor': 'mobile',
        'platform': 'android',
        'brand': a.brand,
        'model': a.model,
        'device': a.device,
        'hardware': a.hardware,
        'sdk_int': a.version.sdkInt,
      };
    }
    if (Platform.isIOS) {
      final i = await _deviceInfo.iosInfo;
      return {
        'form_factor': 'mobile',
        'platform': 'ios',
        'model': i.utsname.machine,
        'name': i.name,
        'system_version': i.systemVersion,
      };
    }
    if (Platform.isWindows) {
      final w = await _deviceInfo.windowsInfo;
      return {
        'form_factor': 'desktop',
        'platform': 'windows',
        'computer_name': w.computerName,
        'cores': w.numberOfCores,
        'system_memory_mb': w.systemMemoryInMegabytes,
      };
    }

    return {'form_factor': 'unknown', 'platform': Platform.operatingSystem};
  }

  Future<Map<String, dynamic>> _cpuSection(Map<String, dynamic> device) async {
    if (Platform.isWindows) {
      return {
        'model': 'Windows CPU (${device['cores'] ?? '?'} cores)',
        'cores': device['cores'],
      };
    }
    return {'model': device['model']?.toString() ?? 'Unknown CPU'};
  }

  Future<Map<String, dynamic>> _gpuSection(Map<String, dynamic> device) async {
    return {
      'model': device['hardware']?.toString() ?? 'Integrated / Unknown GPU',
      'vram_gb': 0,
      'note': Platform.isWindows ? 'Run Start-PCVerseProbe.bat for GPU-Z class data' : null,
    };
  }

  Future<Map<String, dynamic>> _ramSection(Map<String, dynamic> device) async {
    final mb = device['system_memory_mb'];
    if (mb is int) {
      return {'total_gb': (mb / 1024).round()};
    }
    return {'total_gb': 0};
  }

  Future<Map<String, dynamic>> _networkSection() async {
    final conn = await Connectivity().checkConnectivity();
    return {
      'type': conn.name,
      'wifi_standard': conn == ConnectivityResult.wifi ? 'Wi‑Fi' : null,
      'lan_speed_mbps': conn == ConnectivityResult.ethernet ? 1000 : null,
    };
  }
}

class DiagnosticService {
  final String _base = PcverseAppConfig.apiBase;
  final PcverseWindowsAgentClient agent = PcverseWindowsAgentClient();

  /// Same storage key as [ApiClient] so diagnostic history matches catalog/telemetry.
  static Future<String> _fingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    var fp = prefs.getString('_pcverse_fp');
    if (fp == null || fp.isEmpty) {
      fp = const Uuid().v4();
      await prefs.setString('_pcverse_fp', fp);
    }
    return fp;
  }

  Future<Map<String, dynamic>> fetchLive() async {
    final fp = await _fingerprint();
    final res = await http.get(Uri.parse('$_base/diagnostic/live').replace(queryParameters: {'fp': fp}));
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchHistory({int limit = 20}) async {
    final fp = await _fingerprint();
    final res = await http.get(Uri.parse('$_base/diagnostic/history').replace(queryParameters: {
      'limit': '$limit',
      'fp': fp,
    }));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> fetchReport(String token) async {
    final fp = await _fingerprint();
    final res = await http.get(
      Uri.parse('$_base/diagnostic/report/${Uri.encodeComponent(token)}').replace(queryParameters: {'fp': fp}),
    );
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchConfig() async {
    final fp = await _fingerprint();
    final res = await http.get(Uri.parse('$_base/diagnostic/config').replace(queryParameters: {'fp': fp}));
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchRgbCatalog() async {
    final fp = await _fingerprint();
    final res = await http.get(Uri.parse('$_base/diagnostic/rgb/catalog').replace(queryParameters: {'fp': fp}));
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchGames(String q, {int page = 1}) async {
    final fp = await _fingerprint();
    final uri = Uri.parse('$_base/diagnostic/games').replace(queryParameters: {
      'fp': fp,
      if (q.isNotEmpty) 'q': q,
      'page': '$page',
      'per_page': '40',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['games'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> submitFullReport(
    Map<String, dynamic> report, {
    List<String> gameIds = const [],
    String? importFormat,
    String? importContent,
  }) async {
    final payload = Map<String, dynamic>.from(report);
    payload['selected_games'] = gameIds;
    if (importFormat != null && importContent != null) {
      payload['import_format'] = importFormat;
      payload['import_content'] = importContent;
    }

    final endpoint = (report['probe_version'] ?? 0) >= 2 ? 'agent' : 'full';
    final fp = await _fingerprint();
    final res = await http.post(
      Uri.parse('$_base/diagnostic/$endpoint').replace(queryParameters: {'fp': fp}),
      headers: {
        'Content-Type': 'application/json',
        'X-App-Platform': 'mobile',
        'X-PCVERSE-Client': 'pcverse-flutter',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      return {'error': res.body};
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
