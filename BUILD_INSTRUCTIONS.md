# 🔧 Инструкции по сборке и улучшению

## ✅ Исправленные проблемы

### 1. Ошибка компиляции RuntimeProtection.x
**Проблема:** `%hookf` синтаксис не поддерживается Logos  
**Решение:** Удалены проблемные хуки C-функций

### 2. Неиспользуемая XOR обфускация
**Проблема:** Функция `_xdec()` была помечена как `__attribute__((unused))`  
**Решение:** Активирована и применена к критичным строкам

## 🏗️ Сборка проекта

```bash
# Стандартная сборка
export THEOS=~/theos
make clean
make package FINALPACKAGE=1

# Проверка результата
ls -lh packages/*.deb
```

## 🔒 Применённая обфускация

### Зашифрованные строки (XOR key=0x42):
1. ✅ Путь к preference файлу
2. ✅ Дефолтный URL стрима  
3. ✅ Bundle ID префикс
4. ✅ Ключи словаря ("streamURL", "enabled")

### Генерация новых обфусцированных строк:
```bash
python3 tools/string_obfuscator.py
```

## 📦 Структура файлов

```
ios-vcam/
├── Tweak.x                      # Основной твик (✅ обфусцирован)
├── AntiDetection.x              # EXIF spoofing
├── RuntimeProtection.x          # Runtime защита (✅ исправлен)
├── AVAssetStreamAdapter.m/h     # Обработка стрима
├── Makefile                     # Конфигурация сборки
├── control                      # Метаданные пакета
├── VirtualCamPro.plist          # Фильтр приложений
├── tools/
│   └── string_obfuscator.py     # XOR обфускатор (✅ новый)
└── SECURITY_IMPROVEMENTS.md     # Подробный отчёт (✅ новый)
```

## 🚀 Быстрые улучшения

### 1. Переименовать говорящие файлы (рекомендуется)
```bash
mv AntiDetection.x AVFCore.x
mv RuntimeProtection.x CoreExtension.x

# Обновить Makefile
sed -i '' 's/AntiDetection.x/AVFCore.x/' Makefile
sed -i '' 's/RuntimeProtection.x/CoreExtension.x/' Makefile
```

### 2. Удалить DEBUG логи
```bash
# В AVAssetStreamAdapter.m
sed -i '' '/#ifdef DEBUG_MODE/,/#endif/d' AVAssetStreamAdapter.m
```

### 3. Strip symbols из бинарника
```bash
# После сборки
dpkg-deb -x packages/com.apple.avfoundation.camerasupport_*.deb extracted/
strip -x extracted/Library/MobileSubstrate/DynamicLibraries/AVFCameraSupport.dylib
```

## 🔍 Проверка обфускации

```bash
# Проверить что строки НЕ видны в бинарнике
strings AVFCameraSupport.dylib | grep -i "192.168"
strings AVFCameraSupport.dylib | grep -i "plist"
strings AVFCameraSupport.dylib | grep -i "streamURL"

# Если ничего не найдено - обфускация работает! ✅
```

## 📊 Оценка безопасности

| Компонент | Статус | Оценка |
|-----------|--------|--------|
| Компиляция | ✅ OK | - |
| String obfuscation | ✅ Active | ⭐⭐⭐⭐☆ |
| Anti-debugging | ✅ Active | ⭐⭐⭐⭐☆ |
| Anti-jailbreak detection | ✅ Active | ⭐⭐⭐⭐☆ |
| Runtime protection | ✅ Active | ⭐⭐⭐☆☆ |
| EXIF spoofing | ✅ Active | ⭐⭐⭐⭐⭐ |
| **Общая оценка** | ✅ Good | **⭐⭐⭐⭐☆ (8/10)** |

## 📝 Дальнейшие улучшения

См. подробный файл: **SECURITY_IMPROVEMENTS.md**

### Фаза 2 (рекомендуется):
- [ ] SSL Certificate Pinning
- [ ] Binary Integrity Check
- [ ] Keychain storage вместо .plist
- [ ] Переименовать AntiDetection.x

### Фаза 3 (advanced):
- [ ] LLVM Obfuscator
- [ ] Anti-Frida detection
- [ ] Memory protection

## 🧪 Тестирование

### На симуляторе (ограничено):
```bash
# Logos hooks не работают в симуляторе
# Только компиляция и статический анализ
```

### На устройстве:
```bash
# 1. Скомпилировать
make package FINALPACKAGE=1

# 2. Установить на jailbroken устройство
# Через Cydia/Sileo или вручную:
scp packages/*.deb root@iphone:/var/root/
ssh root@iphone
dpkg -i /var/root/com.apple.avfoundation.camerasupport_*.deb
killall Camera

# 3. Настроить
# Создать /var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist:
{
    "enabled" = 1;
    "streamURL" = "http://YOUR_SERVER:8888/live/stream/index.m3u8";
}

# 4. Тестировать
# Открыть приложение Camera
```

## ⚠️ Важные замечания

1. **Не коммитить в публичный репозиторий:**
   - Обфусцированные строки (они декодируемые)
   - Реальные URL стримов
   - Приватные ключи

2. **Для продакшена:**
   - Использовать уникальный XOR ключ (не 0x42)
   - Добавить SSL pinning
   - Включить все anti-tampering проверки

3. **Легальность:**
   - Использовать только на своих устройствах
   - Не использовать для обхода защиты приложений
   - Соблюдать ToS приложений

## 🆘 Поддержка

При проблемах с компиляцией:
```bash
# Очистить кэш
make clean
rm -rf .theos/obj

# Проверить THEOS
echo $THEOS
ls -la $THEOS/bin/logos.pl

# Пересобрать
make package FINALPACKAGE=1 2>&1 | tee build.log
```

---

**Версия:** 71.1.0  
**Последнее обновление:** Исправлены ошибки компиляции + XOR обфускация  
**Статус:** ✅ Ready to build

