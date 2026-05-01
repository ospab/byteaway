import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'features/auth/auth_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();

  final authCubit = AuthCubit();
  runApp(ByteAwayApp(authCubit: authCubit));
  authCubit.bootstrap();
}
