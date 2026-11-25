# Kadraj (iOS Native Port)

Android için geliştirilen **Kadraj** akıllı kamera uygulamasının **Swift / SwiftUI + AVFoundation + Apple Vision + CoreMotion + CoreImage** kullanan native iPhone portudur.

> Not: `.ipa` çıktısı ve iOS derlemesi yalnızca macOS + Xcode ortamında çalışır. Windows üzerinde Xcode bulunmadığı için projeye **GitHub Actions (`macos-latest` + `xcodegen` + `xcodebuild`)** iş akışı eklenmiştir.

## iPhone'unuza Kurulum Adımları (Ücretsiz / Mac Gerekmeden)

1. `Kadraj-iOS` klasörünün içini yeni bir GitHub deposuna (repository) yükleyin (`.github/workflows/build-ipa.yml` dahil).
2. GitHub'da **Actions** sekmesine girin; **`build-kadraj-ios-ipa`** iş akışı otomatik çalışacak ve sonunda **`Kadraj-iOS-IPA`** (`Kadraj-unsigned.ipa`) dosyasını üretecektir. (Dilerseniz `Actions -> build-kadraj-ios-ipa -> Run workflow` ile manuel de tetikleyebilirsiniz.)
3. İndirdiğiniz ZIP içindeki `Kadraj-unsigned.ipa` dosyasını bilgisayarda **Sideloadly** veya iPhone üzerinde **AltStore** kullanarak kendi Apple ID'nizle imzalayıp doğrudan iPhone'unuza kurabilirsiniz.
4. Alternatif olarak bir Mac bilgisayarda `brew install xcodegen && xcodegen generate` komutunu çalıştırıp `Kadraj.xcodeproj` dosyasını Xcode'da açarak kablo ile doğrudan iPhone'unuza yükleyebilirsiniz.

## Özellikler
- **Smart Composition Guidance:** Apple Vision (`VNDetectFaceRectanglesRequest`, `VNRecognizeAnimalsRequest`, `VNClassifyImageRequest`, Saliency) + `CoreMotion` ufuk çizgisi ile en yakın Altın Oran / 1/3 kadraj noktasına yönlendirme.
- **Akıcı Zoom & Tap-to-Focus + EV:** Geniş açıdan (`0.5×`) başlayan donanım rampalı zoom, dokunarak odaklama, dikey güneş pozlama (EV) sürüklemesi.
- **10-bit HLG Video HDR & Post-Processing:** Destekleyen iPhone'larda `HLG_BT2020` 10-bit HDR video kaydı, desteklemeyen cihazlarda güvenli SDR düşüşü; fotoğraf ve videolarda tek dokunuş **Auto HDR**, 6 sinematik/vintage film profili (`Original`, `Teal & Orange`, `Kodak Gold`, `Classic Chrome`, `Moody Matte`, `Noir B&W`) ve `Intensity (%0–100)` ayarı.
- **Pro Settings:** Aspect Ratio (`4:3`, `16:9`, `1:1`), `1080p`/`4K`, `30fps`/`60fps`, HDR `Auto/On/Off`, `3×3 Grid`, `Golden Ratio`, `Horizon Level`, `High Efficiency` vs `Max Quality`, Haptic & Deklanşör Sesi.
