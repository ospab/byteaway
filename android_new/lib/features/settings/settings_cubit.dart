import 'package:flutter_bloc/flutter_bloc.dart';
import '../../app/di.dart';
import '../../core/services/settings_store.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(SettingsState.initial());

  final SettingsStore _store = sl<SettingsStore>();

  void load() {
    emit(state.copyWith(
      protocol: _store.protocol,
      mtu: _store.mtu,
      killSwitch: _store.killSwitch,
      ostpHost: _store.ostpHost,
      ostpPort: _store.ostpPort,
      ostpLocalPort: _store.ostpLocalPort,
      country: _store.country,
      connType: _store.connType,
    ));
  }

  Future<void> setProtocol(String value) async {
    await _store.setProtocol(value);
    emit(state.copyWith(protocol: value));
  }

  Future<void> setMtu(int value) async {
    await _store.setMtu(value);
    emit(state.copyWith(mtu: value));
  }

  Future<void> setKillSwitch(bool value) async {
    await _store.setKillSwitch(value);
    emit(state.copyWith(killSwitch: value));
  }

  Future<void> setOstpHost(String value) async {
    await _store.setOstpHost(value);
    emit(state.copyWith(ostpHost: value));
  }

  Future<void> setOstpPort(int value) async {
    await _store.setOstpPort(value);
    emit(state.copyWith(ostpPort: value));
  }

  Future<void> setOstpLocalPort(int value) async {
    await _store.setOstpLocalPort(value);
    emit(state.copyWith(ostpLocalPort: value));
  }

  Future<void> setCountry(String value) async {
    await _store.setCountry(value);
    emit(state.copyWith(country: value));
  }

  Future<void> setConnType(String value) async {
    await _store.setConnType(value);
    emit(state.copyWith(connType: value));
  }

  void unlockHidden() {
    if (!state.hiddenUnlocked) {
      emit(state.copyWith(hiddenUnlocked: true));
    }
  }
}
