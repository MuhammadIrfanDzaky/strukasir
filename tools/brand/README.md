# Generator logo STRUKASIR

Satu sumber untuk semua logo: geometri mark ada di `build.mjs`. Menjalankannya menulis ulang:

- `docs/brand/*.svg`: logo 4 variasi (lockup, wordmark, mark, sub-mark) + versi reversed & mono, ikon app, ikon Play Store 512
- `app/assets/brand/` (`mark.png`, `mark_reversed.png`, 1x/2x/3x)
- ikon launcher Android (`mipmap-*`: legacy, adaptive foreground, monochrome) dan `drawable-*/launch_mark.png`

```bash
cd tools/brand && npm install && npm run build
```

Warna di `build.mjs` harus sama dengan `app/lib/core/theme/tokens.dart` dan design system.
