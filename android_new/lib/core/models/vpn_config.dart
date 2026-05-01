class VpnConfig {
  final String vlessLink;
  final String assignedIp;
  final String subnet;
  final String gateway;
  final List<String> dns;
  final String tier;
  final int maxSpeedMbps;

  const VpnConfig({
    required this.vlessLink,
    required this.assignedIp,
    required this.subnet,
    required this.gateway,
    required this.dns,
    required this.tier,
    required this.maxSpeedMbps,
  });

  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    final dnsRaw = json['dns'] as List<dynamic>? ?? const [];
    return VpnConfig(
      vlessLink: (json['vless_link'] as String?)?.trim() ?? '',
      assignedIp: (json['assigned_ip'] as String?)?.trim() ?? '10.8.0.2',
      subnet: (json['subnet'] as String?)?.trim() ?? '10.8.0.0/24',
      gateway: (json['gateway'] as String?)?.trim() ?? '10.8.0.1',
      dns: dnsRaw.map((e) => e.toString()).toList(),
      tier: (json['tier'] as String?)?.trim() ?? 'free',
      maxSpeedMbps: (json['max_speed_mbps'] as num?)?.toInt() ?? 10,
    );
  }
}
