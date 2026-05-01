# ByteAway B2B Connector

Linux клиент для подключения к ByteAway residential прокси сети.

## Быстрый старт

```bash
# 1. Скачайте и запустите
chmod +x byteaway_connector.py
python3 byteaway_connector.py --api-key b2b_xxxxxxxxxxxxxxxxxxxx

# 2. Настройте приложение
SOCKS5 хост: 127.0.0.1
SOCKS5 порт: 1080
Username: RU-wifi    # или US-mobile, DE-all
Password: ВАШ_API_КЛЮЧ
```

## Опции

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `--api-key` | обязательно | Ваш API ключ ByteAway |
| `--proxy` | byteaway.ospab.host | Хост SOCKS5 прокси |
| `--port` | 31280 | Порт SOCKS5 прокси |
| `--listen` | 127.0.0.1:1080 | Локальный адрес для прослушивания |

## Примеры

```bash
# Подключение к US прокси через порт 3128
python3 byteaway_connector.py --api-key b2b_xxx --listen 0.0.0.0:3128 --proxy byteaway.ospab.host

# Подключение через мобильные прокси
python3 byteaway_connector.py --api-key b2b_xxx --country US --type mobile
```

## Использование с curl

```bash
curl --socks5 127.0.0.1:1080 -U "RU-wifi:ВАШ_API_КЛЮЧ" https://api.ipify.org?format=json
```

## Использование с браузером

Настройте браузер использовать SOCKS5 прокси:
- **Host:** 127.0.0.1
- **Port:** 1080
- **Username:** RU-wifi (или US-mobile, DE-all)
- **Password:** ваш API ключ

## Типы подключений

- `RU-wifi` - Россия, WiFi
- `US-mobile` - США, мобильная сеть
- `DE-all` - Германия, любой тип

## Требования

```bash
# Ubuntu/Debian
sudo apt install python3

# Запуск без зависимостей (использует только stdlib)
```

## Устранение проблем

```bash
# Проверьте что порт свободен
netstat -tlnp | grep 1080

# Проверьте подключение к прокси
nc -zv byteaway.ospab.host 31280
```
