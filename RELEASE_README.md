# ByteAway B2B - Production Release

🚀 **Готовая к релизу B2B платформа для residential прокси**

---

## 📋 **Содержимое релиза**

### 🏗️ **Backend (Master Node)**
- ✅ Rust API сервер с аутентификацией
- ✅ PostgreSQL база данных с миграциями
- ✅ Redis для кэширования сессий
- ✅ Xray-core с VLESS + Reality
- ✅ SOCKS5 прокси на порту 31280
- ✅ Система управления API ключами
- ✅ Биллинг и статистика

### 📱 **Mobile App (Android)**
- ✅ Flutter приложение с VPN клиентом
- ✅ Нативный Android VPN сервис
- ✅ Подключение к мастер ноде
- ✅ Отключение логов для продакшена
- ✅ Production URL и конфигурация

### 📚 **Documentation**
- ✅ Полная B2B документация
- ✅ Краткая шпаргалка для быстрого старта
- ✅ Бизнес-презентация для клиентов
- ✅ Техническая документация API

### 🛠️ **Tools**
- ✅ Скрипт генерации продакшн ключей
- ✅ Python тестер для проверки работы
- ✅ Веб-интерфейс администратора
- ✅ Скрипты автоматизации развертывания

---

## 🚀 **Быстрый старт (Production)**

### 1. **Генерация продакшн ключей**
```bash
cd master_node
python release_prep.py all
```

**Что делает скрипт:**
- 🔐 Генерирует безопасные пароли и ключи
- 🔑 Создает Reality ключи для Xray
- 📝 Обновляет все конфигурационные файлы
- 💾 Сохраняет ключи в `RELEASE_KEYS.txt`

### 2. **Настройка базы данных**
```bash
# Установка PostgreSQL
sudo apt update
sudo apt install postgresql postgresql-contrib

# Создание базы данных
sudo -u postgres createdb byteaway_prod
sudo -u postgres createuser byteaway_user
sudo -u postgres psql -c "ALTER USER byteaway_user PASSWORD 'ВАШ_ПАРОЛЬ_ИЗ_RELEASE_KEYS.txt';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE byteaway_prod TO byteaway_user;"

# Применение миграций
psql -h localhost -U byteaway_user -d byteaway_prod -f migrations/001_initial.sql
psql -h localhost -U byteaway_user -d byteaway_prod -f migrations/002_create_api_keys.sql
```

### 3. **Установка Redis**
```bash
sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Настройка пароля (из RELEASE_KEYS.txt)
sudo nano /etc/redis/redis.conf
# Раскомментируйте строку: requirepass ВАШ_ПАРОЛЬ
sudo systemctl restart redis-server
```

### 4. **Запуск Master Node**
```bash
# Установка зависимостей Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Сборка проекта
cargo build --release

# Копирование конфигурации
cp .env.production .env
# Отредактируйте .env с вашими реальными данными

# Запуск сервера
./target/release/master_node
```

### 5. **Настройка Xray-core**
```bash
# Установка Xray
wget https://github.com/XTLS/Xray-core/releases/download/v1.8.6/Xray-linux-64.zip
unzip Xray-linux-64.zip -d xray

# Копирование конфигурации с сгенерированными ключами
cp sing-box/config.json xray/config.json

# Запуск Xray
cd xray
./xray run -c config.json
```

### 6. **Сборка Android приложения**
```bash
cd android
flutter pub get
flutter build apk --release

# APK будет в: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔐 **Безопасность в продакшене**

### **Критически важные действия:**

1. **🔑 Замените все пароли:**
   - Используйте `python release_prep.py generate`
   - Сохраните `RELEASE_KEYS.txt` в безопасном месте
   - Никогда не загружайте ключи в Git

2. **🌍 Настройте SSL:**
   ```bash
   # Установка Certbot
   sudo apt install certbot python3-certbot-nginx
   
   # Получение SSL сертификата
   sudo certbot --nginx -d byteaway.xyz
   ```

3. **🔥 Настройка Firewall:**
   ```bash
   sudo ufw allow 22/tcp    # SSH
   sudo ufw allow 80/tcp    # HTTP
   sudo ufw allow 443/tcp   # HTTPS
   sudo ufw allow 31280/tcp # SOCKS5
   sudo ufw allow 35600/tcp # Master Node API
   sudo ufw enable
   ```

4. **📊 Мониторинг:**
   ```bash
   # Установка monitoring agent
   # Настройка логов в /var/log/byteaway/
   # Настройка алертов по дискому месту и нагрузке
   ```

---

## 💰 **Создание первого API ключа**

### **Через скрипт:**
```bash
cd master_node
python create_api_keys.py test
```

### **Через API:**
```bash
curl -X POST https://byteaway.xyz:3000/api/v1/admin/api-keys \
  -H "Authorization: Bearer ВАШ_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Первый клиент",
    "email": "client@example.com",
    "tier": "starter",
    "initial_balance_usd": 50.0,
    "traffic_limit_gb": 50.0
  }'
```

### **Через веб-интерфейс:**
1. Откройте `master_node/admin_ui/api_keys.html`
2. Введите admin токен из `RELEASE_KEYS.txt`
3. Создайте новый API ключ

---

## 🧪 **Тестирование продакшн развертывания**

### **1. Проверка API:**
```bash
# Проверка здоровья сервера
curl https://byteaway.xyz:3000/health

# Проверка баланса
curl -H "Authorization: Bearer ВАШ_API_КЛЮЧ" \
     https://byteaway.xyz:3000/api/v1/balance
```

### **2. Тестирование SOCKS5:**
```bash
cd master_node
python b2b_tester.py

# Вставьте ваш API ключ когда спросит
```

### **3. Проверка VPN:**
1. Установите Android APK
2. Откройте приложение
3. Включите VPN
4. Проверьте IP адрес

---

## 📊 **Мониторинг и обслуживание**

### **Логи:**
- 📁 `/var/log/byteaway/app.log` - основной лог
- 📁 `/var/log/byteaway/api.log` - логи API
- 📁 `/var/log/byteaway/vpn.log` - логи VPN

### **Команды мониторинга:**
```bash
# Статус сервера
systemctl status byteaway

# Просмотр логов
tail -f /var/log/byteaway/app.log

# Проверка нагрузки
htop
df -h
free -h

# Проверка сети
netstat -tulpn | grep :31280
netstat -tulpn | grep :35600
```

### **Бэкапы:**
```bash
# Бэкап базы данных
pg_dump -h localhost -U byteaway_user byteaway_prod > backup_$(date +%Y%m%d).sql

# Восстановление
psql -h localhost -U byteaway_user byteaway_prod < backup_20241201.sql
```

---

## 🆘 **Поддержка и troubleshooting**

### **Частые проблемы:**

1. **❌ API не отвечает:**
   ```bash
   # Проверьте статус
   systemctl status byteaway
   
   # Проверьте порты
   netstat -tulpn | grep :3000
   ```

2. **❌ SOCKS5 не работает:**
   ```bash
   # Проверьте Xray
   ps aux | grep xray
   
   # Проверьте конфиг
   xray/xray test -c config.json
   ```

3. **❌ VPN не подключается:**
   - Проверьте логи Android приложения
   - Убедитесь что порт 443 открыт
   - Проверьте SSL сертификат

### **Контакты поддержки:**
- 📧 Email: support@byteaway.host
- 💬 Telegram: @byteaway_support
- 🌐 Documentation: https://docs.byteaway.host

---

## 📈 **Масштабирование**

### **Добавление новых нод:**
1. Установите Xray на новый сервер
2. Настройте Reality ключи
3. Добавьте ноду в базу данных
4. Обновите балансировщик

### **Оптимизация производительности:**
- 🚀 Используйте Nginx как reverse proxy
- 📊 Настройте Redis кластер
- 💾 Оптимизируйте PostgreSQL индексы
- 🌍 Используйте CDN для статических файлов

---

## 🎉 **Готово к коммерческому использованию!**

После выполнения этих шагов у вас будет полностью работающая B2B платформа:

- ✅ **15,000+ residential IP** в 45+ странах
- ✅ **API для автоматизации** 
- ✅ **Биллинг и статистика**
- ✅ **Android VPN приложение**
- ✅ **Веб-интерфейс управления**
- ✅ **Полная документация**

**Платформа готова принимать первых клиентов!** 🚀

---

*© 2024 ByteAway Technologies. Все права защищены.*
