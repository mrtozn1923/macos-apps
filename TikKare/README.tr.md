[English](README.md) | **Türkçe**

![TıkKare — macOS için ekran görüntüsü aracı](docs/social/tikkare-linkedin-wide.png)

# TıkKare

Menü çubuğunda çalışan, Lightshot benzeri ekran görüntüsü aracı. Apple silicon için
native; hiçbir şey internete yüklenmez, her şey yerelde kalır.

## Özellikler

- **Yakalama:** alan seçimi, tek tıkla pencere, tam ekran, kaydırarak uzun ekran görüntüsü
- **Ekran üstünde düzenleme:** seçimin hemen yanında araç çubuğu; istersen ayrı editör penceresinde aç (yakınlaştırma destekli)
- **Araçlar:** ok, dikdörtgen, elips, kalem, çizgi, metin, vurgulayıcı, bulanıklaştırma, numaralı adım işaretleri, renk ve kalınlık, geri al / yinele
- **OCR:** seçili alandaki metni panoya kopyalar (Türkçe + İngilizce)
- **Çıktı:** panoya kopyala veya PNG olarak kaydet (Retina çözünürlüğü korunur)

## Kısayollar

| Kısayol | İşlev |
|---|---|
| `⌥⇧1` | Alan / pencere |
| `⌥⇧2` | Tam ekran |
| `⌥⇧3` | Kaydırarak yakala (tekrar basınca biter) |
| `⌥⇧4` | Metin yakala (OCR) |

Kısayollar Ayarlar'dan değiştirilebilir.

**Düzenlerken:** `Enter` / `⌘C` kopyala · `⌘S` kaydet · `⌘⇧S` farklı kaydet · `⌘E` editörde aç ·
`⌘Z` / `⌘⇧Z` geri al / yinele · `Esc` iptal ·
`A R E P L T H B N` araçlar · `1`–`8` renkler · `Shift` düz çizgi / kare.

**Seçim:** köşe ve kenar tutamaçlarıyla boyutlandır, kenarından sürükleyerek taşı
(ilk çizimden önce). Seçimi çizerken `Space` basılı tutarsan seçim taşınır.

## Kurulum

### Hazır sürüm

[Releases](https://github.com/mrtozn1923/macos-apps/releases) sayfasından `TikKare.zip` dosyasını indir, `TikKare.app`'i
`Applications` klasörüne taşı.

Uygulama Apple tarafından notarize edilmediği için ilk açılışta macOS onu engeller:

1. `TikKare.app`'i bir kez açmayı dene.
2. **Sistem Ayarları › Gizlilik ve Güvenlik** bölümünde, aşağıdaki **Yine de Aç** düğmesine tıkla.

### Kaynaktan derleme

```bash
git clone https://github.com/mrtozn1923/macos-apps.git
cd macos-apps/TikKare
./scripts/build.sh --install
```

Uygulama `~/Applications/TikKare.app` konumuna kurulur ve açılır. Makinende "Apple Development"
sertifikası varsa onunla imzalanır; yoksa ad-hoc imzalanır. Ad-hoc imzada her yeniden
derlemeden sonra macOS ekran kaydı iznini tekrar ister.

## İzinler

İlk yakalamada **Ekran ve Sistem Sesi Kaydı** izni istenir
(Sistem Ayarları › Gizlilik ve Güvenlik). İzin verdikten sonra TıkKare'yi yeniden başlatman gerekebilir.

## Gereksinimler

macOS 14 veya üstü, Apple silicon.
