# BioBase Logo Export Pack

Generated from: `biobase.logo.v1.png` (867x264)

## Recommended Flutter desktop assets

For the small dashboard/logo area in the upper-left, use one of these:

- `flutter_desktop/biobase_dash_wave_transparent_256x64.png`
- `flutter_desktop/biobase_dash_logo_transparent_256x64.png`
- `flutter_desktop/biobase_icon_monogram_transparent_32.png` for a true square icon slot

For platform app icons:

- Windows: `flutter_desktop/biobase_app_icon_windows.ico`
- macOS: `flutter_desktop/biobase_app_icon_macos.icns`
- Linux: `flutter_desktop/biobase_icon_monogram_dark_512.png`

Example `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/branding/biobase_dash_wave_transparent_256x64.png
    - assets/branding/biobase_dash_logo_transparent_256x64.png
    - assets/branding/biobase_icon_monogram_transparent_32.png
```

Example Flutter widget:

```dart
Image.asset(
  'assets/branding/biobase_dash_wave_transparent_256x64.png',
  height: 32,
  fit: BoxFit.contain,
)
```

## Recommended website assets

Header / nav logo:
- `website/biobase_logo_horizontal_transparent_640w.png`
- `website/biobase_logo_horizontal_transparent.svg`

Landing page hero:
- `website/biobase_landing_hero_1600x900.png`
- `website/biobase_landing_hero_1600x900.webp`

Social sharing / Open Graph:
- `website/biobase_og_image_1200x630.png`
- `website/biobase_og_image_1200x630.webp`

Favicons and PWA:
- `website/favicon.ico`
- `website/favicon.svg`
- `website/favicon-16x16.png`
- `website/favicon-32x32.png`
- `website/apple-touch-icon.png`
- `website/android-chrome-192x192.png`
- `website/android-chrome-512x512.png`
- `website/site.webmanifest`

HTML head snippet:

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#080b12">
<meta property="og:image" content="/biobase_og_image_1200x630.png">
```

Note: the SVG files are wrappers around the raster artwork, not true vector traces. Keep the original high-resolution source if you later want a hand-traced vector logo.
