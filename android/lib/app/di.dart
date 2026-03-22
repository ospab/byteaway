import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../data/datasources/auth_local_ds.dart';
import '../data/datasources/balance_remote_ds.dart';
import '../data/datasources/stats_remote_ds.dart';
import '../data/datasources/node_remote_ds.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/vpn_repository_impl.dart';
import '../data/repositories/node_repository_impl.dart';
import '../data/repositories/stats_repository_impl.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/vpn_repository.dart';
import '../domain/repositories/node_repository.dart';
import '../domain/repositories/stats_repository.dart';
import '../domain/usecases/login_usecase.dart';
import '../domain/usecases/vpn_usecases.dart';
import '../domain/usecases/node_usecases.dart';
import '../domain/usecases/stats_usecases.dart';
import '../presentation/auth/auth_cubit.dart';
import '../presentation/home/home_cubit.dart';
import '../presentation/settings/settings_cubit.dart';
import '../presentation/statistics/statistics_cubit.dart';

final sl = GetIt.instance;

/// Initialize all dependency injection bindings.
Future<void> initDependencies() async {
  // ── External ─────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  // ── Core ─────────────────────────────────────────────
  sl.registerLazySingleton<ApiClient>(() {
    final localDs = sl<AuthLocalDataSource>();
    final token = localDs.getToken();
    return ApiClient(token: token);
  });

  sl.registerLazySingleton<WsClient>(() => WsClient());

  // ── Data Sources ─────────────────────────────────────
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSource(sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<BalanceRemoteDataSource>(
    () => BalanceRemoteDataSource(sl<ApiClient>()),
  );
  sl.registerLazySingleton<StatsRemoteDataSource>(
    () => StatsRemoteDataSource(sl<ApiClient>()),
  );
  sl.registerLazySingleton<NodeRemoteDataSource>(
    () => NodeRemoteDataSource(),
  );

  // ── Repositories ─────────────────────────────────────
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl<AuthLocalDataSource>(), sl<ApiClient>()),
  );
  sl.registerLazySingleton<VpnRepository>(
    () => VpnRepositoryImpl(),
  );
  sl.registerLazySingleton<NodeRepository>(
    () => NodeRepositoryImpl(sl<NodeRemoteDataSource>()),
  );
  sl.registerLazySingleton<StatsRepository>(
    () => StatsRepositoryImpl(
        sl<BalanceRemoteDataSource>(), sl<StatsRemoteDataSource>()),
  );

  // ── Use Cases ────────────────────────────────────────
  sl.registerLazySingleton(() => LoginUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton(() => ConnectVpnUseCase(sl<VpnRepository>()));
  sl.registerLazySingleton(() => DisconnectVpnUseCase(sl<VpnRepository>()));
  sl.registerLazySingleton(() => StartNodeUseCase(sl<NodeRepository>()));
  sl.registerLazySingleton(() => StopNodeUseCase(sl<NodeRepository>()));
  sl.registerLazySingleton(() => GetBalanceUseCase(sl<StatsRepository>()));
  sl.registerLazySingleton(
      () => GetTrafficHistoryUseCase(sl<StatsRepository>()));

  // ── Cubits ───────────────────────────────────────────
  sl.registerLazySingleton<AuthCubit>(
    () => AuthCubit(sl<LoginUseCase>(), sl<AuthRepository>()),
  );
  sl.registerFactory<HomeCubit>(
    () => HomeCubit(
      connectVpn: sl<ConnectVpnUseCase>(),
      disconnectVpn: sl<DisconnectVpnUseCase>(),
      startNode: sl<StartNodeUseCase>(),
      stopNode: sl<StopNodeUseCase>(),
      getBalance: sl<GetBalanceUseCase>(),
      vpnRepository: sl<VpnRepository>(),
      nodeRepository: sl<NodeRepository>(),
      authLocalDs: sl<AuthLocalDataSource>(),
    ),
  );
  sl.registerFactory<SettingsCubit>(
    () => SettingsCubit(sl<AuthLocalDataSource>()),
  );
  sl.registerFactory<StatisticsCubit>(
    () => StatisticsCubit(sl<GetTrafficHistoryUseCase>()),
  );
}
