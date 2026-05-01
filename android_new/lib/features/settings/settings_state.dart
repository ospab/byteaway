import 'package:equatable/equatable.dart';

class SettingsState extends Equatable {
  final String protocol;
  final int mtu;
  final bool killSwitch;
  final String ostpHost;
  final int ostpPort;
  final int ostpLocalPort;
  final String country;
  final String connType;
  final bool hiddenUnlocked;

  const SettingsState({
    required this.protocol,
    required this.mtu,
    required this.killSwitch,
    required this.ostpHost,
    required this.ostpPort,
    required this.ostpLocalPort,
    required this.country,
    required this.connType,
    required this.hiddenUnlocked,
  });

  factory SettingsState.initial() => const SettingsState(
        protocol: 'vless',
        mtu: 1500,
        killSwitch: false,
        ostpHost: 'byteaway.xyz',
        ostpPort: 8443,
        ostpLocalPort: 1088,
        country: 'RU',
        connType: 'wifi',
        hiddenUnlocked: false,
      );

  SettingsState copyWith({
    String? protocol,
    int? mtu,
    bool? killSwitch,
    String? ostpHost,
    int? ostpPort,
    int? ostpLocalPort,
    String? country,
    String? connType,
    bool? hiddenUnlocked,
  }) {
    return SettingsState(
      protocol: protocol ?? this.protocol,
      mtu: mtu ?? this.mtu,
      killSwitch: killSwitch ?? this.killSwitch,
      ostpHost: ostpHost ?? this.ostpHost,
      ostpPort: ostpPort ?? this.ostpPort,
      ostpLocalPort: ostpLocalPort ?? this.ostpLocalPort,
      country: country ?? this.country,
      connType: connType ?? this.connType,
      hiddenUnlocked: hiddenUnlocked ?? this.hiddenUnlocked,
    );
  }

  @override
  List<Object?> get props => [
        protocol,
        mtu,
        killSwitch,
        ostpHost,
        ostpPort,
        ostpLocalPort,
        country,
        connType,
        hiddenUnlocked,
      ];
}
