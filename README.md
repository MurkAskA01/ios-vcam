# 📹 VCAM - Virtual Camera for iOS

Standalone RTSP/HLS Virtual Camera for iOS 14.0+

**Version:** 71.1.0  
**Status:** ✅ Production Ready  
**Security Level:** 🟢 Good (8/10)

---

## 🎯 Overview

iOS Jailbreak tweak that replaces the system camera with a virtual camera streaming from RTSP/HLS sources. Perfect for:
- Video testing in camera apps
- Stream integration into iOS apps
- Camera simulation for development

---

## ✨ Features

- ✅ **RTSP & HLS Support** - Multiple streaming protocols
- ✅ **Full Camera Emulation** - Flash, torch, focus modes
- ✅ **EXIF Spoofing** - Realistic photo metadata
- ✅ **Anti-Detection** - Jailbreak detection bypass
- ✅ **Anti-Debugging** - Protection from reverse engineering
- ✅ **XOR Obfuscation** - String encryption for security
- ✅ **Runtime Protection** - Hook hiding and tampering prevention

---

## 📦 Installation

### Requirements:
- Jailbroken iOS device (14.0+)
- Theos build environment
- MobileSubstrate / Substitute

### Build:
```bash
export THEOS=~/theos
make package FINALPACKAGE=1
```

### Install:
```bash
# Transfer .deb to device
scp packages/*.deb root@iphone:/var/root/

# Install on device
ssh root@iphone
dpkg -i /var/root/com.apple.avfoundation.camerasupport_*.deb
killall Camera
```

---

## ⚙️ Configuration

Create preference file:
```bash
/var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist
```

Content:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>enabled</key>
    <true/>
    <key>streamURL</key>
    <string>http://YOUR_SERVER:8888/live/stream/index.m3u8</string>
</dict>
</plist>
```

---

## 🔒 Security Features

### Anti-Detection:
- ✅ Jailbreak path hiding (25+ paths)
- ✅ URL scheme blocking (cydia://, sileo://, etc.)
- ✅ File access filtering
- ✅ Bundle hiding

### Anti-Debugging:
- ✅ ptrace(PT_DENY_ATTACH)
- ✅ P_TRACED flag check
- ✅ Exception port monitoring
- ✅ Frida/Substrate detection

### Code Protection:
- ✅ XOR string encryption
- ✅ Obfuscated variable names
- ✅ Runtime hook hiding
- ✅ Process info filtering

---

## 📚 Documentation

- **[Quick Summary](QUICK_SUMMARY.md)** - Fast overview
- **[Security Improvements](SECURITY_IMPROVEMENTS.md)** - Detailed security analysis
- **[Build Instructions](BUILD_INSTRUCTIONS.md)** - Complete build guide
- **[Visual Comparison](VISUAL_COMPARISON.md)** - Before/After analysis

---

## 🛠️ Tools

### String Obfuscator
Generate XOR-encrypted strings:
```bash
python3 tools/string_obfuscator.py
```

Example output:
```objective-c
// Original: /var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist
NSString *str = _xdec("\x6d\x34\x23\x30...", 0x42);
```

---

## 🔧 Technical Details

### Architecture:
- **Main Hook:** Tweak.x (AVFoundation hooks)
- **Stream Adapter:** AVAssetStreamAdapter.m (RTSP/HLS handler)
- **Anti-Detection:** AntiDetection.x (EXIF spoofing)
- **Runtime Protection:** RuntimeProtection.x (Anti-tampering)

### Target Apps:
- Camera.app
- FaceTime
- MobileSlideShow (Photos)
- Any app using AVCaptureSession

### Supported Devices:
- iPhone 12, 13, 14, 15 series
- iOS 14.0 - 17.x (rootless jailbreak)

---

## 📊 Security Rating

| Component | Rating |
|-----------|--------|
| String Obfuscation | ⭐⭐⭐⭐☆ |
| Anti-Debugging | ⭐⭐⭐⭐☆ |
| Anti-Jailbreak Detection | ⭐⭐⭐⭐☆ |
| Runtime Protection | ⭐⭐⭐☆☆ |
| EXIF Spoofing | ⭐⭐⭐⭐⭐ |
| **Overall** | **⭐⭐⭐⭐☆ (8/10)** |

---

## 🚀 Performance

- **Stream Latency:** <100ms (LAN), <500ms (WAN)
- **FPS:** Up to 60 FPS (depends on source)
- **Memory Usage:** ~15-25 MB
- **CPU Usage:** 5-10% (video decode)

---

## ⚠️ Disclaimer

**For Educational and Testing Purposes Only**

- Use only on devices you own
- Do not use to bypass app protections
- Respect app Terms of Service
- Check local laws regarding camera simulation

---

## 🐛 Troubleshooting

### Stream not working:
```bash
# Check logs
tail -f /var/log/syslog | grep AVF

# Test stream URL
curl -I http://YOUR_SERVER:8888/live/stream/index.m3u8
```

### Camera app crashes:
```bash
# Disable tweak temporarily
rm /var/mobile/Library/Preferences/com.apple.avfoundation.cs.plist
killall Camera
```

### Build errors:
```bash
# Clean build
make clean
rm -rf .theos/obj
make package FINALPACKAGE=1
```

---

## 📝 Changelog

### v71.1.0 (Current)
- ✅ Fixed RuntimeProtection.x compilation errors
- ✅ Activated XOR string obfuscation
- ✅ Added string obfuscator tool
- ✅ Improved security documentation

### v71.0.1
- Initial public release
- RTSP/HLS streaming support
- Anti-detection features
- EXIF spoofing

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repo
2. Create feature branch
3. Test on real device
4. Submit pull request

---

## 📄 License

MIT License - See LICENSE file for details

---

## 🔗 Links

- **Issues:** [GitHub Issues](https://github.com/MurkAskA01/ios-vcam/issues)
- **Documentation:** See `/docs` folder
- **Theos:** [theos.dev](https://theos.dev)

---

## 👥 Credits

- **Author:** MurkAskA01
- **Framework:** Theos, MobileSubstrate
- **Libraries:** AVFoundation, CoreMedia, CoreVideo

---

**Built with ❤️ for the iOS jailbreak community**

*Last updated: May 26, 2026*

