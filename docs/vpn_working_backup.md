# Рабочая резервная копия конфигурации (Sing-Box 1.13+ для Android)

В данном документе зафиксированы рабочие конфигурации Dart (Flutter) и Kotlin (Android), которые успешно запускаются в условиях последних версий ядра **Sing-Box 1.13+** с поддержкой Hysteria2 и VLESS.

---

## 1. Конфигурация Dart (Flutter) - `home_cubit.dart`

Код отвечает за отправку правильных данных в нативную часть:

```dart
// В методе toggleVpn() файла android/lib/presentation/home/home_cubit.dart
if (vpnProtocol == 'hy2') {
   AppLogger.log('VPN: HY2 test protocol selected. Constructing HY2 config for testing...');
   String host = 'byteaway.xyz';
   if (vlessLink != null && vlessLink.contains('@')) {
     final parts = vlessLink.split('@');
     if (parts.length > 1) {
       host = parts[1].split(':').first.split('?').first;
     }
   }
   payloadForNative = jsonEncode({
        'vless_link': 'hy2://byteaway_hy2_secret@$host:4433?sni=$host#free',
        'tier': tier,
        'max_speed_mbps': maxSpeed,
   });
}

// Передача полной конфигурации в нативный слой Kotlin
AppLogger.log('VPN: calling native method, protocol=$vpnProtocol, configLength=${safeConfig.length}');
final finalConfig = vpnProtocol == 'hy2' ? payloadForNative : safeConfig;
final success = vpnProtocol == 'ostp'
    ? await _connectVpnOstp(finalConfig)
    : await _connectVpn(finalConfig);
```

---

## 2. Конфигурация Kotlin (Android) - `ByteAwayForegroundService.kt`

Шаблоны для генерации Sing-Box JSON, исключающие deprecated outbounds и устаревшие форматы DNS-адресов.

### VLESS Генератор (`wrapVlessToJson`)
```kotlin
private fun wrapVlessToJson(vlessLink: String, tier: String = "free", maxSpeedMbps: Int = 10, fd: Int = -1): String {
    // ... парсинг VLESS-ссылки ...
    val fdConfig = if (fd > 0) ",\n              \"file_descriptor\": $fd" else ""

    return """
    {
      "log": { "level": "info" },
      "inbounds": [
        {
          "type": "tun",
          "tag": "tun-in",
          "interface_name": "tun0",
          "address": [ "172.19.0.1/30" ]$fdConfig,
          "mtu": 1500,
          "auto_route": false,
          "strict_route": false,
          "stack": "system"
        }
      ],
      "outbounds": [
        {
          "type": "vless",
          "tag": "vless-out",
          "server": "$host",
          "server_port": $port,
          "uuid": "$uuid",
          "flow": "xtls-rprx-vision",
          "tls": {
            "enabled": true,
            "server_name": "$sni",
            "utls": { "enabled": true, "fingerprint": "chrome" },
            "reality": {
              "enabled": true,
              "public_key": "$pubKey",
              "short_id": "$shortId"
            }
          }
        },
        { "type": "direct", "tag": "direct-out" }
      ],
      "dns": {
        "servers": [
          {
            "tag": "dns-remote",
            "type": "udp",
            "server": "1.1.1.1"
          }
        ]
      },
      "route": {
         "auto_detect_interface": false,
         "final": "vless-out",
         "rules": [
           { "action": "sniff" },
           { "protocol": "dns", "action": "hijack-dns" },
           { "action": "sniff" }
         ]
      }
    }
    """.trimIndent()
}
```

### Hysteria2 Генератор (`wrapHy2ToJson`)
```kotlin
private fun wrapHy2ToJson(hy2Link: String, tier: String = "free", maxSpeedMbps: Int = 10, fd: Int = -1): String {
    // ... парсинг HY2-ссылки ...
    val fdConfig = if (fd > 0) ",\n              \"file_descriptor\": $fd" else ""

    return """
    {
      "log": { "level": "info" },
      "inbounds": [
        {
          "type": "tun",
          "tag": "tun-in",
          "interface_name": "tun0",
          "address": [ "172.19.0.1/30" ]$fdConfig,
          "mtu": 1500,
          "auto_route": false,
          "strict_route": false,
          "stack": "system"
        }
      ],
      "outbounds": [
        {
          "type": "hysteria2",
          "tag": "hy2-out",
          "server": "$host",
          "server_port": $port,
          "password": "$password",
          "tls": {
            "enabled": true,
            "server_name": "$sni",
            "insecure": true
          }
        },
        { "type": "direct", "tag": "direct-out" }
      ],
      "dns": {
        "servers": [
          {
            "tag": "dns-remote",
            "type": "udp",
            "server": "1.1.1.1"
          }
        ]
      },
      "route": {
         "auto_detect_interface": false,
         "final": "hy2-out",
         "rules": [
           { "action": "sniff" },
           { "protocol": "dns", "action": "hijack-dns" },
           { "action": "sniff" }
         ]
      }
    }
    """.trimIndent()
}
```
