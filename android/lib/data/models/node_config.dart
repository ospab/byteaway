class NodeConfig {
  final String token;
  final String? coreConfigJson;
  final int? mtu;

  NodeConfig({required this.token, this.coreConfigJson, this.mtu});

  factory NodeConfig.fromJson(Map<String, dynamic> json) {
    return NodeConfig(
      token: json['token'],
      coreConfigJson: json['core_config_json'] ?? json['xray_config_json'],
      mtu: json['mtu'],
    );
  }
}
