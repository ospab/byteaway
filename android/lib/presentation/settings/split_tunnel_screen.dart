import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_scaffold.dart';

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

enum SplitTunnelMode {
  bypass,
  proxy,
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  static const _channel = MethodChannel('com.ospab.byteaway/app');
  static const _modeKey = 'split_tunnel_mode';
  List<AppInfo> _allApps = [];
  List<AppInfo> _filteredApps = [];
  Set<String> _excluded = {};
  bool _isLoading = true;
  bool _isApplying = false;
  String _searchQuery = '';
  bool _showSystemApps = true;
  SplitTunnelMode _mode = SplitTunnelMode.bypass;
  String? _selfPackage;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMode();
    _loadSelfPackage();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterApps();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final List<dynamic> appsRaw =
          await _channel.invokeMethod('getInstalledApps');
      final List<dynamic> excludedRaw =
          await _channel.invokeMethod('getExcludedApps');

      setState(() {
        _allApps = appsRaw.map((e) => AppInfo.fromMap(e)).toList();
        // Sort alphabetically by app name
        _allApps.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _filteredApps = _allApps;
        _excluded = Set<String>.from(excludedRaw.cast<String>());
        _isLoading = false;
      });
      await _ensureSelfExcluded();
      _filterApps();
    } catch (e) {
      debugPrint('Failed to load apps: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterApps() {
    _filteredApps = _allApps.where((app) {
      // Filter by search query
      final matchesSearch = _searchQuery.isEmpty ||
          app.name.toLowerCase().contains(_searchQuery) ||
          app.pkg.toLowerCase().contains(_searchQuery);

      // Filter by system apps toggle
      final matchesSystemFilter = _showSystemApps || !app.isSystem;

      return matchesSearch && matchesSystemFilter;
    }).toList();
  }

  Future<void> _toggleApp(String pkg, bool selected) async {
    if (_selfPackage == pkg) return;
    // In bypass mode, selected means bypass (exclude).
    // In proxy mode, selected means proxy (not excluded).
    final bool bypass = _mode == SplitTunnelMode.bypass ? selected : !selected;
    final String action = bypass ? 'addExclude' : 'removeExclude';
    try {
      await _channel.invokeMethod(action, {'pkg': pkg});
      setState(() {
        if (bypass) {
          _excluded.add(pkg);
        } else {
          _excluded.remove(pkg);
        }
      });
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Failed to toggle app $pkg: $e');
    }
  }

  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey)?.toLowerCase();
    if (raw == 'proxy') {
      setState(() {
        _mode = SplitTunnelMode.proxy;
      });
    }
  }

  Future<void> _saveMode(SplitTunnelMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode == SplitTunnelMode.proxy ? 'proxy' : 'bypass');
  }

  Future<void> _loadSelfPackage() async {
    try {
      final package = await PackageInfo.fromPlatform();
      setState(() {
        _selfPackage = package.packageName;
      });
      await _ensureSelfExcluded();
    } catch (_) {
      // Ignore package lookup errors.
    }
  }

  Future<void> _ensureSelfExcluded() async {
    final pkg = _selfPackage;
    if (pkg == null || pkg.isEmpty) return;
    if (_excluded.contains(pkg)) return;
    try {
      await _channel.invokeMethod('addExclude', {'pkg': pkg});
      setState(() {
        _excluded.add(pkg);
      });
    } catch (e) {
      debugPrint('Failed to lock self package exclusion: $e');
    }
  }

  Future<void> _applyMode(SplitTunnelMode mode) async {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _isApplying = true;
    });
    await _saveMode(mode);
    await _ensureSelfExcluded();
    setState(() {
      _isApplying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: 'Split-Tunnel',
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60), // Account for GlassScaffold app bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Bypass', style: TextStyle(color: Colors.white)),
                      selected: _mode == SplitTunnelMode.bypass,
                      selectedColor: AppTheme.primary.withOpacity(0.3),
                      onSelected: _isApplying
                          ? null
                          : (v) => _applyMode(SplitTunnelMode.bypass),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Proxy', style: TextStyle(color: Colors.white)),
                      selected: _mode == SplitTunnelMode.proxy,
                      selectedColor: AppTheme.primary.withOpacity(0.3),
                      onSelected: _isApplying
                          ? null
                          : (v) => _applyMode(SplitTunnelMode.proxy),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Поиск по имени или пакету...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixIcon:
                      Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // System apps filter toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.apps,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Показывать системные приложения',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _showSystemApps,
                    onChanged: (value) {
                      setState(() {
                        _showSystemApps = value;
                        _filterApps();
                      });
                    },
                    activeColor: AppTheme.primary,
                  ),
                ],
              ),
            ),
            // Apps count
            if (!_isLoading)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Найдено приложений: ${_filteredApps.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _mode == SplitTunnelMode.bypass
                          ? 'Bypass: ${_excluded.length}'
                          : 'Proxy: ${_filteredApps.length - _excluded.length}',
                      style: TextStyle(
                        color: AppTheme.primary.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _filteredApps.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                color: Colors.white.withOpacity(0.5),
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Приложения не найдены',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 16,
                                ),
                              ),
                              if (!_showSystemApps)
                                Text(
                                  'Попробуйте включить системные приложения',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, i) {
                            final app = _filteredApps[i];
                            final isBypassed = _excluded.contains(app.pkg);
                            final isSelected = _mode == SplitTunnelMode.bypass
                                ? isBypassed
                                : !isBypassed;
                            return _buildAppItem(app, isSelected, isBypassed);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppItem(AppInfo app, bool isSelected, bool isBypassed) {
    final isLocked = app.pkg == _selfPackage;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: SwitchListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.name,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (app.isSystem)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  'СИСТ',
                  style: TextStyle(
                    color: Colors.orange.withOpacity(0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              app.pkg,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _mode == SplitTunnelMode.bypass
                  ? (isSelected ? 'Bypass через сеть' : 'Через VPN')
                  : (isSelected ? 'Через VPN' : 'Bypass через сеть'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
            if (app.isSystem)
              Text(
                'UID: ${app.uid}',
                style: TextStyle(
                  color: Colors.orange.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            if (isLocked)
              Text(
                'ByteAway всегда в исключениях',
                style: TextStyle(
                  color: Colors.redAccent.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
          ],
        ),
        secondary: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: app.isSystem
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: app.icon.isNotEmpty
                ? Image.memory(
                    app.icon,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 40,
                      height: 40,
                      color: app.isSystem
                          ? Colors.orange.withOpacity(0.1)
                          : AppTheme.primary.withOpacity(0.1),
                      child: Icon(
                        app.isSystem ? Icons.settings : Icons.android,
                        color: app.isSystem
                            ? Colors.orange.withOpacity(0.7)
                            : AppTheme.primary,
                        size: 24,
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: app.isSystem
                        ? Colors.orange.withOpacity(0.1)
                        : AppTheme.primary.withOpacity(0.1),
                    child: Icon(
                      app.isSystem ? Icons.settings : Icons.android,
                      color: app.isSystem
                          ? Colors.orange.withOpacity(0.7)
                          : AppTheme.primary,
                      size: 24,
                    ),
                  ),
          ),
        ),
        // Selected meaning depends on mode.
        value: isSelected,
        activeColor: AppTheme.primary,
        inactiveThumbColor: Colors.grey.withOpacity(0.5),
        inactiveTrackColor: Colors.grey.withOpacity(0.2),
        onChanged: isLocked || _isApplying ? null : (v) => _toggleApp(app.pkg, v),
      ),
    );
  }
}

class AppInfo {
  final String pkg;
  final String name;
  final Uint8List icon;
  final bool isSystem;
  final int uid;

  AppInfo({
    required this.pkg,
    required this.name,
    required this.icon,
    this.isSystem = false,
    this.uid = 0,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    final iconData = map['icon'];
    Uint8List iconBytes;

    if (iconData != null && iconData is List) {
      try {
        iconBytes = Uint8List.fromList(List<int>.from(iconData));
      } catch (e) {
        // Fallback if conversion fails
        iconBytes = Uint8List(0);
      }
    } else {
      iconBytes = Uint8List(0);
    }

    return AppInfo(
      pkg: map['package'] ?? '',
      name: map['label'] ?? 'Unknown',
      icon: iconBytes,
      isSystem: map['isSystem'] ?? false,
      uid: map['uid'] ?? 0,
    );
  }
}
