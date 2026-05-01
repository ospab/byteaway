# ByteAway

ByteAway is a distributed platform combining a high-speed secure VPN client with a residential proxy network. The project allows users to bypass network restrictions using modern protocols while optionally sharing a portion of their Internet bandwidth to participate in a distributed B2B proxy mesh network.

[Русская версия (Russian Version)](#русская-версия) | [English Version](#english-version)

---

## Русская версия

### Основные возможности

#### Клиентское приложение (Android / Flutter)
- **Пользовательский интерфейс**: Построен на базе Material 3 с использованием эффектов Glassmorphism.
- **Поддерживаемые протоколы**: VLESS (XTLS-Reality), OSTP и Hysteria2 для обхода систем глубокого анализа пакетов (DPI).
- **Раздельное туннелирование (Split-Tunneling)**: Настройка исключений из VPN-туннеля для конкретных приложений. Само приложение ByteAway исключается автоматически для предотвращения сетевых петель.
- **Функционал прокси-узла (Node)**: Предоставление части интернет-канала в B2B-сеть. Передача данных осуществляется по протоколам QUIC или WebSocket.
- **Интеграция Sing-Box**: Сетевое ядро Sing-Box встроено через gomobile и библиотеку boxwrapper для управления трафиком через TUN-интерфейс.

#### Серверная часть (Master Node)
- **Управление и оркестрация**: Координирующий сервер написан на Rust, обеспечивает управление соединениями и распределение трафика.
- **Интерфейс API**: REST API для авторизации пользователей, управления лимитами и динамического создания конфигураций.
- **B2B-гейтвей**: SOCKS5/HTTP-сервер для приема клиентского трафика и его передачи на доступные мобильные узлы.

### Архитектура проекта

Проект разделен на следующие директории:

- `/android` - Исходный код мобильного клиента (Flutter, Kotlin, Go).
- `/master_node` - Серверная часть для маршрутизации и биллинга (Rust).
- `/ostp` - Код реализации протокола OSTP (Ospab Stealth Transport Protocol).
- `/b2b_connector` - Модули для подключения B2B клиентов.
- `/docs/` - Подробная техническая документация.

### Сборка приложения

Для автоматизации сборки предусмотрен скрипт PowerShell `build.ps1`.

```powershell
# Сборка релизной версии
.\build.ps1 -BuildType release -PublishMode none

# Сборка отладочной версии
.\build.ps1 -BuildType debug -PublishMode none
```

Результаты сборки помещаются в директорию `/builded`.

### Документация

Подробная информация о компонентах системы на русском языке:
- [Архитектура и компоненты](docs/ru/architecture.md)
- [Мобильное приложение](docs/ru/mobile_app.md)
- [Мастер-нода и Сеть](docs/ru/master_node.md)
- [Дизайн и интерфейс](docs/ru/design.md)

---

## English Version

### Core Features

#### Client Application (Android / Flutter)
- **User Interface**: Based on Material 3 principles with Glassmorphism visual styles.
- **Supported Protocols**: VLESS (XTLS-Reality), OSTP, and Hysteria2 to bypass Deep Packet Inspection (DPI) systems.
- **Split-Tunneling**: Direct configuration of VPN tunnel routing rules. The ByteAway application is excluded by default to eliminate routing loops.
- **Proxy Node Capabilities**: Bandwidth sharing with the B2B network. Communication utilizes QUIC or WebSocket protocols.
- **Sing-Box Integration**: The Sing-Box core is embedded via gomobile and the boxwrapper library for direct traffic parsing via the TUN interface.

#### Server Infrastructure (Master Node)
- **Orchestration**: The backend server is built in Rust to manage proxy connections and direct bandwidth load balancing.
- **API Endpoints**: REST API handlers for user authentication, connection usage tracking, and configuration rendering.
- **B2B Gateway**: SOCKS5/HTTP proxy interface that redirects incoming B2B traffic to registered mobile nodes.

### Project Directory Structure

The project repository includes the following subdirectories:

- `/android` - Source code for the mobile client (Flutter, Kotlin, Go).
- `/master_node` - Server modules for traffic routing and automated billing (Rust).
- `/ostp` - Reference implementation for the OSTP protocol.
- `/b2b_connector` - Components used to manage incoming B2B client requests.
- `/docs/` - Full technical documentation files.

### Application Build Process

A PowerShell script `build.ps1` handles the compilation and packaging of binaries.

```powershell
# Build release version
.\build.ps1 -BuildType release -PublishMode none

# Build debug version
.\build.ps1 -BuildType debug -PublishMode none
```

All compiled binaries are saved to the `/builded` directory.

### Project Documentation

Detailed system documentation in English:
- [System Architecture](docs/en/architecture.md)
- [Mobile Application](docs/en/mobile_app.md)
- [Master Node and Networking](docs/en/master_node.md)
- [Design Principles](docs/en/design.md)
