import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/services/settings_store.dart';
import '../core/services/vpn_repository.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);
  sl.registerSingleton<ApiClient>(ApiClient());
  sl.registerSingleton<SettingsStore>(SettingsStore(prefs));
  sl.registerSingleton<VpnRepository>(VpnRepository());
}
