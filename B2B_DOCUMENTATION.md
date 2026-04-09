# ByteAway B2B: Документация для бизнеса

## 📋 Оглавление

1. [Обзор сервиса](#обзор-сервиса)
2. [Архитектура системы](#архитектура-системы) 
3. [Как это работает](#как-это-работает)
4. [Подключение к сервису](#подключение-к-сервису)
5. [API документация](#api-документация)
6. [Тарифные планы](#тарифные-планы)
7. [Интеграция с кодом](#интеграция-с-кодом)
8. [Мониторинг и статистика](#мониторинг-и-статистика)
9. [FAQ](#faq)
10. [Техническая поддержка](#техническая-поддержка)

---

## 🎯 Обзор сервиса

**ByteAway B2B** - это P2P сеть резидентных прокси, которая позволяет бизнесу получать доступ к реальным residential IP адресам по всему миру.

### Ключевые преимущества:

✅ **Настоящие residential IP** - от реальных пользователей, не дата-центров  
✅ **Гео-таргетинг** - выбирайте нужные страны и типы соединений  
✅ **Высокая скорость** - прямые соединения через мобильные сети  
✅ **Анонимность** - трафик маршрутизируется через множество узлов  
✅ **Масштабируемость** - тысячи узлов по всему миру  
✅ **Экономичность** - в 10 раз дешевле традиционных прокси

---

## 🏗️ Архитектура системы

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   B2B Клиент    │    │   Мастер Нода   │    │   Мобильные     │
│                 │    │                 │    │   Узлы (P2P)    │
│ • SOCKS5 клиент │◄──►│ • Балансировщик │◄──►│ • Android/IOS   │
│ • API ключ      │    │ • Биллинг       │    │ • Residential  │
│ • Гео-фильтры   │    │ • Мониторинг    │    │   IP адреса    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Компоненты системы:

**🔧 Мастер Нода (Master Node)**
- Центральный сервер управления
- Балансировщик нагрузки
- Биллинг и статистика
- WebSocket туннели к узлам

**📱 Мобильные Узлы (Nodes)**
- Android приложения пользователей
- Резидентные IP адреса
- WiFi + Зарядка для шеринга
- Xray-core (VLESS + Reality)

**🌐 B2B Клиенты**
- SOCKS5 прокси клиенты
- HTTP API для управления
- Гео-таргетинг
- Статистика в реальном времени

---

## ⚙️ Как это работает

### Шаг 1: Регистрация и получение API ключа

1. Зарегистрируйтесь на платформе ByteAway
2. Получите уникальный API ключ
3. Пополните баланс

### Шаг 2: Настройка гео-таргетинга

```
Формат фильтра: {СТРАНА}-{ТИП_СОЕДИНЕНИЯ}

Страны:
- RU - Россия
- US - США  
- DE - Германия
- GB - Великобритания
- FR - Франция
- IT - Италия
- ES - Испания
- NL - Нидерланды

Типы соединений:
- wifi - WiFi подключения
- mobile - мобильные сети
- all - все типы

Примеры:
- RU-wifi - российские WiFi
- US-mobile - американские мобильные
- DE-all - все немецкие IP
```

### Шаг 3: Подключение через SOCKS5

```python
import socks
import socket
import requests

# Настройка SOCKS5 прокси
SOCKS5_HOST = "byteaway.xyz"
SOCKS5_PORT = 31280
API_KEY = "ваш_api_ключ"
FILTER = "RU-wifi"  # Российские WiFi

# Установка прокси
socks.set_default_proxy(socks.SOCKS5, SOCKS5_HOST, SOCKS5_PORT, True, FILTER, API_KEY)
socket.socket = socks.socksocket

# Проверка IP
response = requests.get("https://api.ipify.org?format=json")
print(f"Ваш IP: {response.json()['ip']}")
```

---

## 🔌 Подключение к сервису

### 1. SOCKS5 Прокси

**Основной метод подключения:**
```
Хост: byteaway.xyz
Порт: 31280
Имя пользователя: {фильтр}
Пароль: {api_ключ}
```

### 2. Python Пример

```python
import socks
import socket
import requests

class ByteAwayProxy:
    def __init__(self, api_key, filter_country="RU-wifi"):
        self.api_key = api_key
        self.filter = filter_country
        self.host = "byteaway.xyz"
        self.port = 31280
        
    def setup_proxy(self):
        """Настройка SOCKS5 прокси"""
        socks.set_default_proxy(
            socks.SOCKS5, 
            self.host, 
            self.port, 
            True, 
            self.filter, 
            self.api_key
        )
        socket.socket = socks.socksocket
        
    def test_connection(self):
        """Тест подключения"""
        try:
            response = requests.get("https://api.ipify.org?format=json", timeout=10)
            return response.json()['ip']
        except Exception as e:
            print(f"Ошибка: {e}")
            return None

# Использование
proxy = ByteAwayProxy("your_api_key", "US-mobile")
proxy.setup_proxy()
ip = proxy.test_connection()
print(f"Резидентный IP: {ip}")
```

### 3. JavaScript/Node.js Пример

```javascript
const { SocksProxyAgent } = require('socks-proxy-agent');

const API_KEY = 'your_api_key';
const FILTER = 'RU-wifi';
const PROXY_URL = `socks5://${FILTER}:${API_KEY}@byteaway.xyz:31280`;

const agent = new SocksProxyAgent(PROXY_URL);

// Использование с fetch
fetch('https://api.ipify.org?format=json', { agent })
  .then(res => res.json())
  .then(data => console.log(`IP: ${data.ip}`));
```

---

## 📚 API документация

### Базовый URL: `http://byteaway.xyz:35600`

### Аутентификация
```
Authorization: Bearer {api_ключ}
```

### Эндпоинты:

#### 1. Получить баланс
```http
GET /api/v1/balance
```

**Ответ:**
```json
{
  "balance_usd": 25.50,
  "vpn_days_remaining": 30,
  "total_traffic_gb": 150.25
}
```

#### 2. Статистика
```http
GET /api/v1/stats
```

**Ответ:**
```json
{
  "shared_traffic_gb": 2.5,
  "current_speed_mbps": 5.2,
  "active_sessions": 3,
  "uptime_seconds": 3600
}
```

#### 3. Доступные узлы
```http
GET /api/v1/nodes?filter={фильтр}
```

**Ответ:**
```json
{
  "nodes": [
    {
      "country": "RU",
      "city": "Moscow",
      "ip_type": "wifi",
      "speed_mbps": 50,
      "active": true
    }
  ],
  "total_available": 1250
}
```

---

## 💰 Тарифные планы

### 🥉 Starter Pack - $50/месяц
- 50 GB трафика
- До 5 одновременных сессий
- 3 страны
- Базовая поддержка

### 🥈 Business Pack - $200/месяц  
- 250 GB трафика
- До 20 одновременных сессий
- 10 стран
- Приоритетная поддержка
- API доступ

### 🥇 Enterprise Pack - $500/месяц
- 1 TB трафика
- Неограниченные сессии
- Все страны
- Выделенная поддержка
- Кастомные фильтры

### 💎 Custom - от $1000/месяц
- Индивидуальные условия
- Выделенные узлы
- Белый IP
- SLA гарантии

---

## 🔧 Интеграция с кодом

### Python библиотека

```python
import requests
import socks
import socket
from typing import Optional

class ByteAwayClient:
    def __init__(self, api_key: str, base_url: str = "http://byteaway.xyz:35600"):
        self.api_key = api_key
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {api_key}'
        })
    
    def get_balance(self) -> dict:
        """Получить баланс"""
        response = self.session.get(f"{self.base_url}/api/v1/balance")
        return response.json()
    
    def get_stats(self) -> dict:
        """Получить статистику"""
        response = self.session.get(f"{self.base_url}/api/v1/stats")
        return response.json()
    
    def setup_socks5_proxy(self, filter_str: str = "RU-wifi"):
        """Настроить SOCKS5 прокси"""
        socks.set_default_proxy(
            socks.SOCKS5,
            "byteaway.xyz",
            31280,
            True,
            filter_str,
            self.api_key
        )
        socket.socket = socks.socksocket
    
    def test_proxy(self, filter_str: str = "RU-wifi") -> Optional[str]:
        """Протестировать прокси"""
        self.setup_socks5_proxy(filter_str)
        try:
            response = requests.get("https://api.ipify.org?format=json", timeout=10)
            return response.json()['ip']
        except Exception as e:
            print(f"Ошибка прокси: {e}")
            return None

# Пример использования
client = ByteAwayClient("your_api_key")
balance = client.get_balance()
print(f"Баланс: ${balance['balance_usd']}")

ip = client.test_proxy("US-mobile")
print(f"IP из США: {ip}")
```

### Интеграция с Selenium

```python
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
import socks
import socket

# Настройка прокси
socks.set_default_proxy(socks.SOCKS5, "byteaway.xyz", 31280, True, "RU-wifi", "your_api_key")
socket.socket = socks.socksocket

# Chrome с прокси
chrome_options = Options()
chrome_options.add_argument("--proxy-server=socks5://byteaway.xyz:31280")

driver = webdriver.Chrome(options=chrome_options)
driver.get("https://whatismyipaddress.com")
print(driver.title)
```

---

## 📊 Мониторинг и статистика

### Веб-панель управления

Доступна по адресу: `https://byteaway.xyz/dashboard`

**Функционал:**
- 📈 Графики потребления трафика
- 🗺️ Карта активных узлов
- 💰 Финансовая статистика
- ⚡ Скорость соединений
- 🔍 История сессий

### Метрики в реальном времени

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "active_nodes": 15420,
  "total_traffic_today_gb": 2500.5,
  "average_speed_mbps": 25.3,
  "success_rate": 99.7,
  "countries_active": 45
}
```

---

## ❓ FAQ

### Q: Как быстро начинается работа?
**A:** Мгновенно после получения API ключа. Первое подключение занимает < 5 секунд.

### Q: Насколько стабильны соединения?
**A:** 99.7% uptime. Мобильные узлы могут отключаться, но система автоматически переключает на другие.

### Q: Какие типы трафика поддерживаются?
**A:** HTTP/HTTPS, SOCKS5, TCP. UDP не поддерживается.

### Q: Можно ли использовать для парсинга?
**A:** Да, идеально подходит для web scraping, SEO инструментов, маркетинговых платформ.

### Q: Как billed трафик?
**A:** Только входящий трафик считается. 1 GB = ~$5 в зависимости от тарифа.

### Q: Есть ли лимиты по скорости?
**A:** Зависит от узла и тарифа. В среднем 10-100 Mbps на узел.

### Q: Как обеспечить анонимность?
**A:** Каждый запрос проходит через разные узлы, IP меняются динамически.

### Q: Что если узел отключился?
**A:** Система автоматически находит замену < 1 секунду.

---

## 🛠️ Техническая поддержка

### Контакты

- 📧 Email: `support@byteaway.host`
- 💬 Telegram: `@byteaway_support`
- 🌐 Web: `https://byteaway.host/support`

### Время работы

- 🕘 Стандартная поддержка: 9:00-18:00 МСК
- 🚨 Экстренные случаи: 24/7 для Enterprise клиентов

### Типичные проблемы

1. **"Connection refused"**
   - Проверьте API ключ
   - Убедитесь что баланс положительный
   - Проверьте формат фильтра

2. **"Slow connection"**
   - Попробуйте другой фильтр страны
   - Проверьте время пинга до узла
   - Используйте несколько потоков

3. **"Authentication failed"**
   - Проверьте правильность API ключа
   - Убедитесь что аккаунт активен

---

## 📋 Чек-лист для быстрого старта

1. ✅ Зарегистрироваться на платформе
2. ✅ Получить API ключ
3. ✅ Пополнить баланс
4. ✅ Выбрать нужный фильтр страны
5. ✅ Настроить SOCKS5 прокси в коде
6. ✅ Протестировать соединение
7. ✅ Начать использовать!

---

## 🎉 Заключение

**ByteAway B2B** - это современное решение для доступа к резидентным IP адресам по всему миру. 

**Наши преимущества:**
- 🌍 45+ стран покрытия
- 📱 15,000+ активных узлов  
- ⚡ Скорость до 100 Mbps
- 💰 Цены в 10 раз ниже конкурентов
- 🔒 Высокий уровень анонимности

**Начните сегодня!** 🚀

Регистрация: https://byteaway.host/b2b
Документация: https://docs.byteaway.host
Поддержка: support@byteaway.host

---

*© 2024 ByteAway Technologies. Все права защищены.*
