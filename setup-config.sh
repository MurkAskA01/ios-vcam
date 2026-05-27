#!/bin/bash

# iOS Virtual Camera - Setup Script
# Создание конфигурационного файла

PREF_PATH="/var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist"

echo "📹 iOS Virtual Camera - Setup"
echo "================================"
echo ""

# Запрос URL стрима
read -p "Введите URL стрима (например: http://192.168.1.10:8888/live/stream/index.m3u8): " STREAM_URL

if [ -z "$STREAM_URL" ]; then
    STREAM_URL="http://127.0.0.1:8888/live/stream/index.m3u8"
    echo "⚠️  URL не указан, используем localhost: $STREAM_URL"
fi

# Создание plist файла
cat > "$PREF_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>enabled</key>
    <true/>
    <key>streamURL</key>
    <string>$STREAM_URL</string>
</dict>
</plist>
EOF

# Установка прав
chmod 644 "$PREF_PATH"
chown mobile:mobile "$PREF_PATH"

echo ""
echo "✅ Конфигурация создана: $PREF_PATH"
echo ""
echo "📝 Содержимое:"
cat "$PREF_PATH"
echo ""
echo "🔄 Перезапустите приложения:"
echo "   killall Camera"
echo "   killall FaceTime"
echo ""
echo "✅ Готово!"
