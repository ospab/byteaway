#!/usr/bin/env python3
"""
Скрипт для создания тестовых API ключей ByteAway B2B
"""

import requests
import sys

# Конфигурация
API_BASE = "https://byteaway.xyz/api/v1/admin"
ADMIN_TOKEN = "admin_token_123"  # TODO: Реальная аутентификация

def create_test_api_key():
    """Создает тестовый API ключ"""
    
    # Данные тестового клиента
    test_client = {
        "name": "Тестовый клиент",
        "email": "test@byteaway.host",
        "tier": "starter",
        "initial_balance_usd": 50.0,
        "traffic_limit_gb": 50.0,
        "max_sessions": 5,
        "allowed_countries": ["RU", "US", "DE"],
        "expires_days": 365
    }
    
    try:
        response = requests.post(
            f"{API_BASE}/api-keys",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {ADMIN_TOKEN}"
            },
            json=test_client
        )
        
        if response.status_code == 200:
            api_key = response.json()
            print("✅ Тестовый API ключ создан успешно!")
            print(f"🔑 API Ключ: {api_key['api_key']}")
            print(f"🆔 Key ID: {api_key['key_id']}")
            print(f"👤 Клиент: {api_key['name']}")
            print(f"💰 Баланс: ${api_key['balance_usd']:.2f}")
            print(f"📊 Трафик: {api_key['traffic_limit_gb']:.1f}GB")
            print(f"🌍 Страны: {', '.join(api_key['allowed_countries'] or [])}")
            
            # Сохраняем ключ в файл для тестов
            with open("test_api_key.txt", "w") as f:
                f.write(f"API_KEY={api_key['api_key']}\n")
                f.write(f"KEY_ID={api_key['key_id']}\n")
                f.write("FILTER=RU-wifi\n")
            
            print("\n💾 Ключ сохранен в test_api_key.txt")
            return api_key['api_key']
            
        else:
            print(f"❌ Ошибка создания API ключа: {response.status_code}")
            print(f"Response: {response.text}")
            return None
            
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        return None

def test_api_key(api_key):
    """Тестирует созданный API ключ"""
    
    print("\n🧪 Тестируем API ключ...")
    
    # Тест получения баланса
    try:
        response = requests.get(
            "http://localhost:3000/api/v1/balance",
            headers={"Authorization": f"Bearer {api_key}"}
        )
        
        if response.status_code == 200:
            balance = response.json()
            print(f"✅ Баланс: ${balance['balance_usd']:.2f}")
            print(f"✅ Дней VPN: {balance['vpn_days_remaining']}")
        else:
            print(f"❌ Ошибка баланса: {response.status_code}")
            
    except Exception as e:
        print(f"❌ Ошибка теста баланса: {e}")
    
    # Тест получения статистики
    try:
        response = requests.get(
            "http://localhost:3000/api/v1/stats",
            headers={"Authorization": f"Bearer {api_key}"}
        )
        
        if response.status_code == 200:
            stats = response.json()
            print(f"✅ Трафик: {stats['shared_traffic_gb']:.1f}GB")
            print(f"✅ Скорость: {stats['current_speed_mbps']:.1f}Mbps")
            print(f"✅ Сессии: {stats['active_sessions']}")
        else:
            print(f"❌ Ошибка статистики: {response.status_code}")
            
    except Exception as e:
        print(f"❌ Ошибка теста статистики: {e}")

def create_business_client():
    """Создает API ключ для бизнес-клиента"""
    
    business_client = {
        "name": "ООО ВебСкрапер",
        "email": "business@webscraper.ru",
        "tier": "business",
        "initial_balance_usd": 200.0,
        "traffic_limit_gb": 250.0,
        "max_sessions": 20,
        "allowed_countries": ["RU", "US", "DE", "GB", "FR", "IT", "ES", "NL"],
        "expires_days": 365
    }
    
    try:
        response = requests.post(
            f"{API_BASE}/api-keys",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {ADMIN_TOKEN}"
            },
            json=business_client
        )
        
        if response.status_code == 200:
            api_key = response.json()
            print("✅ Business API ключ создан!")
            print(f"🔑 Ключ: {api_key['api_key'][:20]}...")
            return api_key['api_key']
        else:
            print(f"❌ Ошибка: {response.status_code}")
            return None
            
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        return None

def main():
    """Главная функция"""
    
    print("🚀 ByteAway B2B - Создание тестовых API ключей")
    print("=" * 50)
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "test":
            api_key = create_test_api_key()
            if api_key:
                test_api_key(api_key)
                
        elif command == "business":
            create_business_client()
            
        elif command == "help":
            print("Использование:")
            print("  python create_api_keys.py test     - создать тестовый ключ")
            print("  python create_api_keys.py business - создать бизнес ключ")
            print("  python create_api_keys.py help     - показать помощь")
            
        else:
            print(f"❌ Неизвестная команда: {command}")
            print("Используйте 'help' для помощи")
    else:
        # По умолчанию создаем тестовый ключ
        api_key = create_test_api_key()
        if api_key:
            test_api_key(api_key)

if __name__ == "__main__":
    main()
