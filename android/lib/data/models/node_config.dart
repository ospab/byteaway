class NodeConfig {
  final String token;
  final int? mtu;

  NodeConfig({required this.token, this.mtu});

  factory NodeConfig.fromJson(Map<String, dynamic> json) {
    return NodeConfig(
      token: json['token'],
      mtu: json['mtu'],
    );
  }
}
