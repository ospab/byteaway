# ByteAway B2B: Краткая шпаргалка

## 🚀 Быстрый старт (5 минут)

### 1. Подключение
```python
import socks
import socket
import requests

# Настройка
SOCKS5_HOST = "byteaway.xyz"
SOCKS5_PORT = 31280
API_KEY = "ваш_api_ключ"
FILTER = "RU-wifi"  # Российские WiFi

# Установка прокси
socks.set_default_proxy(socks.SOCKS5, SOCKS5_HOST, SOCKS5_PORT, True, FILTER, API_KEY)
socket.socket = socks.socksocket

# Проверка
response = requests.get("https://api.ipify.org?format=json")
print(f"IP: {response.json()['ip']}")
```

### 2. Фильтры стран
```
RU-wifi    # Российские WiFi
US-mobile  # Американские мобильные
DE-all     # Все немецкие IP
GB-wifi    # Британские WiFi
FR-mobile  # Французские мобильные
IT-all     # Все итальянские
ES-wifi    # Испанские WiFi
NL-mobile  # Голландские мобильные
```

### 3. Тарифы
- **Starter**: $50/мес - 50GB - 5 сессий
- **Business**: $200/мес - 250GB - 20 сессий  
- **Enterprise**: $500/мес - 1TB - ∞ сессий

### 4. Поддержка
- 📧 support@byteaway.host
- 💬 @byteaway_support
- 🌐 https://byteaway.host/support

---

## 📊 Примеры использования

### Selenium WebDriver
```python
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

options = Options()
options.add_argument("--proxy-server=socks5://byteaway.xyz:31280")

driver = webdriver.Chrome(options=options)
driver.get("https://whatismyipaddress.com")
```

### AIOHTTP
```python
import aiohttp
import asyncio

async def fetch():
    proxy = "socks5://RU-wifi:api_key@byteaway.xyz:31280"
    connector = aiohttp.TCPConnector()
    async with aiohttp.ClientSession() as session:
        async with session.get("https://api.ipify.org?format=json") as resp:
            return await resp.json()
```

### Requests с сессией
```python
import requests
session = requests.Session()
session.proxies = {
    'http': 'socks5://RU-wifi:api_key@byteaway.xyz:31280',
    'https': 'socks5://RU-wifi:api_key@byteaway.xyz:31280'
}
response = session.get("https://api.ipify.org?format=json")
```

---

## ⚡ Производительность

- **Средняя скорость**: 25-50 Mbps
- **Ping**: 50-200ms
- **Uptime**: 99.7%
- **Активные узлы**: 15,000+
- **Страны**: 45+

---

## 🔧 Решение проблем

### "Connection refused"
```python
# Проверьте API ключ и баланс
import requests
balance = requests.get("http://byteaway.xyz:35600/api/v1/balance", 
                       headers={"Authorization": "Bearer your_api_key"})
print(balance.json())
```

### Медленная скорость
```python
# Попробуйте другой фильтр
filters = ["RU-wifi", "US-mobile", "DE-all", "GB-wifi"]
for f in filters:
    try:
        socks.set_default_proxy(socks.SOCKS5, "byteaway.xyz", 31280, True, f, API_KEY)
        ip = requests.get("https://api.ipify.org?format=json", timeout=5)
        print(f"{f}: {ip.json()['ip']}")
        break
    except:
        continue
```

---

## 📈 Мониторинг

### API статистика
```python
import requests

def get_stats(api_key):
    response = requests.get("http://byteaway.xyz:35600/api/v1/stats",
                           headers={"Authorization": f"Bearer {api_key}"})
    return response.json()

stats = get_stats("your_api_key")
print(f"Трафик: {stats['shared_traffic_gb']}GB")
print(f"Скорость: {stats['current_speed_mbps']}Mbps")
print(f"Сессии: {stats['active_sessions']}")
```

---

## 🎯 Советы

1. **Используйте несколько потоков** для максимальной скорости
2. **Меняйте фильтры** для разных задач
3. **Следите за балансом** через API
4. **Кэшируйте подключения** для повторных запросов
5. **Используйте retry** для нестабильных соединений

---

**Готово к работе! 🚀**

Регистрация: https://byteaway.host/b2b
Документация: https://docs.byteaway.host
