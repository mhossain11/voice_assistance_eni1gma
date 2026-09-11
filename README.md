# EN1GMA

EN1GMA একটি sample Android voice-assistant prototype। এটি `Enigma` wake word শুনে, Android speech-to-text ব্যবহার করে, Gemini-তে প্রশ্ন পাঠায় এবং TTS দিয়ে উত্তর বলে।

## যা লাগবে

- Flutter SDK
- Android Studio / Android SDK
- একটি physical Android device (microphone ও wake word পরীক্ষা করার জন্য)
- Gemini API key

## 1. Model files যাচাই করুন

এই তিনটি file অবশ্যই এখানে থাকতে হবে:

```text
android/app/src/main/assets/
  enigma.onnx
  melspectrogram.onnx
  model_info.json
```

`enigma.onnx` অন্য folder-এ রাখবেন না। Native Android foreground service এই assets folder থেকেই model load করে।

## 2. Gemini API key সেট করুন

Project root-এ `.env` file আছে। এতে নিজের key দিন:

```env
GEMINI_API_KEY=YOUR_GEMINI_API_KEY
GEMINI_MODEL=gemini-3.6-flash
```

`.env` Git ignore করা আছে। এটি commit বা share করবেন না। Template হিসেবে `.env.example` আছে।

> সতর্কতা: এই sample app-এ `.env` APK-এর সঙ্গে bundle হয়। তাই এটি শুধুমাত্র demo/development key-এর জন্য ব্যবহার করুন। Production app-এর জন্য backend proxy ব্যবহার করা উচিত।

## 3. Dependencies নামান

Project folder থেকে চালান:

```powershell
flutter pub get
```

## 4. ফোন connect করে চালান

Developer options এবং USB debugging চালু করে ফোন connect করুন। তারপর:

```powershell
flutter devices
flutter run
```

প্রথমবার Android microphone permission চাইবে। **Allow** দিন। Permission deny করলে app crash করবে না, কিন্তু wake word ও STT কাজ করবে না।

## 5. APK build করুন

```powershell
flutter build apk --debug
```

APK সাধারণত এখানে পাওয়া যায়:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## ব্যবহার

1. App চালু হলে status হবে **Sleeping**।
2. বলুন: **Enigma**।
3. Status হবে **Listening**। প্রশ্ন বলুন।
4. App **Thinking** → **Speaking** → আবার **Listening** হবে।
5. একই session-এ আরও প্রশ্ন করতে পারবেন; প্রতিবার `Enigma` বলার দরকার নেই।
6. ঘুম পাড়াতে বলুন: `sleep`, `go to sleep`, `enigma sleep`, `stop listening`, `that's all`।

Sleep command Gemini-তে পাঠানো হয় না। এটি TTS/STT বন্ধ করে conversation history clear করে আবার wake-word mode চালু করে।

## Background behavior

Wake-word detector Android foreground service হিসেবে চলে এবং notification দেখায়:

```text
EN1GMA — Listening for "Enigma"
```

App background বা screen off হলেও Android অনুমতি দিলে wake detection চলতে পারে। Android battery policy, device manufacturer, বা app process kill হওয়ার কারণে সব device-এ একই আচরণ নিশ্চিত নয়।

## Troubleshooting

### `MICROPHONE_PERMISSION_REQUIRED`

Android Settings → Apps → EN1GMA → Permissions থেকে Microphone **Allow** করুন। এরপর app আবার চালান।

### Gemini is not configured

`.env`-এ `GEMINI_API_KEY` আছে কি না যাচাই করুন, তারপর `flutter pub get` এবং `flutter run` আবার চালান।

### Kotlin Gradle Plugin warning

`flutter_tts` বা `speech_to_text` সংক্রান্ত Built-in Kotlin warning এখনকার build failure নয়। ভবিষ্যতের Flutter compatibility-এর জন্য plugin update হলে upgrade করুন।

### Kotlin compile error

নতুন code নেওয়ার পরে clean build করতে পারেন:

```powershell
flutter clean
flutter pub get
flutter build apk --debug
```

## Validation commands

```powershell
flutter analyze
flutter test
flutter build apk --debug
```
