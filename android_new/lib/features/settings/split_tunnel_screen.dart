import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/models/app_info.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  static const MethodChannel _channel = MethodChannel(AppConstants.splitTunnelChannel);
  final TextEditingController _searchController = TextEditingController();

  List<AppInfo> _allApps = [];
  List<AppInfo> _filteredApps = [];
  Set<String> _excluded = {};
  bool _isLoading = true;
  bool _showSystemApps = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final appsRaw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      final excludedRaw = await _channel.invokeMethod<List<dynamic>>('getExcludedApps');
      final apps = (appsRaw ?? []).map((e) => AppInfo.fromMap(e)).toList();
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      setState(() {
        _allApps = apps;
        _excluded = Set<String>.from(excludedRaw ?? const []);
        _filteredApps = apps;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredApps = _allApps.where((app) {
        final matches = query.isEmpty ||
            app.label.toLowerCase().contains(query) ||
            app.packageName.toLowerCase().contains(query);
        final matchesSystem = _showSystemApps || !app.isSystem;
        return matches && matchesSystem;
      }).toList();
    });
  }

  Future<void> _toggleExclude(AppInfo app, bool excluded) async {
    try {
      await _channel.invokeMethod(excluded ? 'addExclude' : 'removeExclude', {'pkg': app.packageName});
      setState(() {
        if (excluded) {
          _excluded.add(app.packageName);
        } else {
          _excluded.remove(app.packageName);
        }
      });
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Split-Tunnel',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по имени или пакету',
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text('Системные приложения', style: TextStyle(color: AppTheme.textSecondary)),
                const Spacer(),
                Switch(
                  value: _showSystemApps,
                  onChanged: (value) {
                    setState(() {
                      _showSystemApps = value;
                      _applyFilter();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: _filteredApps.length,
                    itemBuilder: (context, i) {
                      final app = _filteredApps[i];
                      final excluded = _excluded.contains(app.packageName);
                      return _appTile(app, excluded);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _appTile(AppInfo app, bool excluded) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        value: excluded,
        onChanged: (value) => _toggleExclude(app, value),
        title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          app.packageName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        secondary: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: app.icon.isEmpty
              ? Container(
                  width: 40,
                  height: 40,
                  color: Colors.white.withOpacity(0.08),
                  child: const Icon(Icons.apps, color: AppTheme.textSecondary),
                )
              : Image.memory(app.icon, width: 40, height: 40, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
