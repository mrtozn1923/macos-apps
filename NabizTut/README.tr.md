[English](README.md) | **Türkçe**

# NabızTut

macOS için masaüstü uptime izleyici. Web sitelerini, API'leri ve sunucuları belirlediğin
aralıkla kontrol eder; ayakta olup olmadıklarını, ne kadar hızlı cevap verdiklerini ve yakın
geçmişlerini masaüstünde duran küçük bir panelde gösterir. Tamamen yerel: sunucu yok, hesap yok.

> Arayüz macOS dilini takip eder: Türkçe ya da İngilizce.

## Özellikler

- **Masaüstü paneli:** Duvar kağıdının üstünde, pencerelerin altında durur; tüm Space'lerde görünür.
  Her site bir satır: durum, son cevap süresi, 24 saatlik uptime ve son 1 saatin mini grafiği.
  Düşen siteler en üste çıkar.
- **Kontrol türleri:**
  - **HTTP(S):** durum kodu, cevap süresi, beklenen kodlar (örn. `200-299, 301`),
    cevapta kelime kontrolü (içerir / içermez), özel metot, header ve gövde,
    yönlendirme ayarı, SSL sertifikası bitiş uyarısı
  - **Ping** (ICMP)
  - **TCP port** (veritabanı, SSH, herhangi bir servis)
- **Bildirimler:** Site düşünce macOS bildirimi ve uyarı sesi, geri gelince kesinti süresiyle
  bildirim, SSL sertifikası bitmeden bir kez uyarı. Site bazında bildirim açma/kapama.
- **Geçmiş:** 24 saat / 7 gün / 30 gün cevap süresi grafiği ve işaretli kesintiler,
  uptime %, ortalama ve p95 cevap süresi, kesinti listesi.
- **Menü çubuğu ikonu:** Yeşil / sarı / kırmızı genel durum ve tüm sitelerin hızlı listesi.
- **Gizli header'lar** (API anahtarı, token) ayar dosyasında değil, macOS Anahtar Zinciri'nde saklanır.

## Kibar istekler

Çok sık istek atmak engellenmeye yol açabilir; NabızTut trafiği düşük tutar:

- Aralıklar: 1, 2, 5, 10, 15, 30 veya 60 dakika (en az 1, varsayılan 5).
- Kontroller zamana yayılır, hepsi aynı anda gönderilmez.
- Bir site ancak **iki** başarısız kontrolden sonra "düştü" sayılır; doğrulama ilk hatadan
  30 saniye sonra yapılır. Her şey yolundayken fazladan istek gitmez.
- Sayfa içeriği gerekmiyorsa `HEAD` isteği kullanır ve kendini açık bir `User-Agent` ile tanıtır.
- Mac uykudayken veya çevrimdışıyken kontroller durur; bu süre kesinti sayılmaz.

## Veri

- Ham kontroller 7 gün tutulur, sonra saatlik özete dönüştürülüp 30 gün saklanır.
- Her şey `~/Library/Application Support/NabizTut/` altındadır:
  `monitors.json` (siteler; okunabilir, yedeklemesi kolay) ve `history.sqlite`.

## Kullanım

- **Site ekle:** Menü çubuğu ikonu › *Site ekle…* (ilk açılışta form kendiliğinden açılır).
  *Test et* ile kaydetmeden önce tek seferlik kontrol yapılır.
- **Paneli taşı:** Üst çubuğundan sürükle.
- **Paneli boyutlandır:** Menü çubuğu ikonu › *Paneli boyutlandır…*, kenarlardan sürükle, sonra *Bitti*.
- **Detay:** Paneldeki bir satıra tıkla.

## Kurulum

### Hazır sürüm

[Releases](https://github.com/mrtozn1923/macos-apps/releases) sayfasından
[`NabizTut.zip`](https://github.com/mrtozn1923/macos-apps/releases/download/nabiztut-v1.0.0/NabizTut.zip)
dosyasını indir, `NabizTut.app`'i `Uygulamalar` klasörüne taşı.

Uygulama Apple tarafından notarize edilmediği için ilk açılışta macOS onu engeller:

1. `NabizTut.app`'i bir kez açmayı dene.
2. **Sistem Ayarları › Gizlilik ve Güvenlik** bölümünde **Yine de Aç**'a tıkla.
3. Bildirim izni istendiğinde izin ver; böylece bir site düştüğünde haber alırsın.

### Kaynaktan derleme

```bash
git clone https://github.com/mrtozn1923/macos-apps.git
cd macos-apps/NabizTut
./scripts/build.sh --install
```

Uygulama `~/Applications/NabizTut.app` konumuna kurulur ve açılır. Makinende "Apple Development"
sertifikası varsa onunla imzalanır; yoksa ad-hoc imzalanır.

## Gereksinimler

macOS 14 veya üstü, Apple silicon.
