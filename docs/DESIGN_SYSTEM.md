# 🎨 Libris Design System
**Unified Cross-Platform Design Specifications for Mobile (Flutter) & Web (Next.js 16)**

---

## 1. Brand Identity & Visual Direction

Libris is an editorial book discovery and personal learning platform designed around the visual identity of a modern literary journal paired with an intellectual private library:
- **Intellectual Serenity & Focus:** Calm, deep, distraction-free matte surfaces that prioritize reading and discovery over visual noise.
- **Editorial Elegance:** Expressive serif display typography (`Playfair Display`, `Outfit`) paired with crystal-clear sans-serif interface text (`Inter`) and technical monospace (`JetBrains Mono`).
- **Curated Pastel Palettes:** 6 harmonious palettes (Classic Editorial, Lavender Mist, Sage Green, Powder Blue, Warm Peach, Soft Rose) with tailored Light and Dark variants.
- **Tactile Depth & Matte Restraint:** Controlled matte layer depth, subtle glass elevation with performance fallbacks, and zero gratuitous neon or clutter.
- **Model A Semantic Integrity:** Absolute separation between Personal Favorites and Reading Milestones (`want_to_read`, `reading`, `finished`), with instant optimistic UI and deterministic rollback.

---

## 2. Color Palette & Semantic Tokens

### 2.1 Complete Semantic Color Roles (Web & Flutter Parity)

| Semantic Role | Web CSS Variable | Mobile Flutter Token | Role / Semantic Meaning |
| :--- | :--- | :--- | :--- |
| `background` | `--background` | `palette.backgroundDark` / `Light` | Root application canvas |
| `surface` | `--surface` | `palette.surfaceDark` / `Light` | Standard card and container surface |
| `surfaceElevated`| `--surface-elevated` | `palette.surfaceDarkHighlight` | Elevated sheets, floating modals, dropdowns |
| `surfaceSubtle` | `--surface-subtle` | `palette.surfaceDarkHighlight` (0.5 op) | Input fields, search bars, subtle chips |
| `textPrimary` | `--text-primary` | `DesignSystem.textDarkPrimary` / `Light` | Primary titles, headlines, high-contrast labels |
| `textSecondary` | `--text-secondary` | `DesignSystem.textDarkSecondary` / `Light`| Subtitles, body descriptions, authors |
| `textMuted` | `--text-muted` | `DesignSystem.textDarkSecondary` (muted) | Captions, timestamps, secondary metadata |
| `border` | `--border` | `DesignSystem.borderDark` / `Light` | Card borders and visual delimiters |
| `divider` | `--divider` | `Theme.colorScheme.outline` (0.1 op) | Thin separation lines |
| `accent` | `--accent` | `palette.accent` | Discovery highlights, AI badge, sparks |
| `accentForeground`| `--accent-foreground`| `DesignSystem.accentForeground` | Text on top of accent surfaces |
| `focus` | `--focus` | `DesignSystem.focus` | Focus-visible keyboard outlines |
| `link` | `--link` | `DesignSystem.link` | Hyperlinks and interactive text |
| `success` | `--success` | `DesignSystem.success` | Successful operations and toasts |
| `warning` | `--warning` | `DesignSystem.warning` | Warnings and cautions |
| `error` | `--error` | `DesignSystem.error` | Error states and destructive alerts |
| `favorite` | `--favorite` | `DesignSystem.favorite` | Heart icon, favorites collection |
| `reading` | `--reading` | `DesignSystem.statusReading` | Currently reading badge (Amber) |
| `wantToRead` | `--wantToRead` | `DesignSystem.statusWantToRead` | Reading queue badge (Sky blue) |
| `finished` | `--finished` | `DesignSystem.statusFinished` | Completed reading badge (Emerald) |
| `like` | `--like` | `DesignSystem.statusLike` | Recommendation seed signal (Indigo) |
| `dislike` | `--dislike` | `DesignSystem.statusDislike` | Recommendation exclusion signal (Slate) |
| `disabled` | `--disabled` | `DesignSystem.disabled` | Inactive controls and disabled buttons |
| `overlay` | `--overlay` | `DesignSystem.overlay` | Modal backdrops and drawer scrims |

---

## 3. The 6 Curated Palettes

| Palette ID | Name | Dark Background | Light Background | Primary Accent | Editorial Mood |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `editorial` | **Classic Editorial** | `#0F172A` (Slate 900) | `#F8FAFC` (Slate 50) | `#6366F1` (Indigo 500) | Intellectual literary review |
| `lavender` | **Lavender Mist** | `#161329` (Twilight Violet)| `#F7F5FC` (Soft Violet) | `#A78BFA` (Amethyst) | Dreamy, reflective reading |
| `sage` | **Sage Green** | `#121D17` (Deep Forest) | `#F2F7F4` (Muted Mint) | `#34D399` (Sage Green) | Grounded, calm focus |
| `powder_blue`| **Powder Blue** | `#0C1929` (Nordic Twilight)| `#F0F7FF` (Crystalline) | `#38BDF8` (Sky Azure) | Crisp, contemporary library |
| `peach` | **Warm Peach** | `#221611` (Parchment Night)| `#FDF6F0` (Warm Apricot) | `#FB923C` (Tuscan Sun) | Cozy antiquarian bookshop |
| `rose` | **Soft Rose** | `#241219` (Dusty Crimson) | `#FDF2F4` (Delicate Rose) | `#FB7185` (Soft Crimson)| Poetic, artistic atmosphere |

---

## 4. Typography System & Scalability

### 4.1 Cross-Platform Font Families
- **Web:**
  - `serif`: `'Playfair Display', Georgia, serif`
  - `sans`: `'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
  - `mono`: `'JetBrains Mono', ui-monospace, monospace`
- **Mobile (Flutter):**
  - `editorial` / `sans`: `GoogleFonts.outfit` (display) + `GoogleFonts.inter` (body)
  - `serif`: `GoogleFonts.playfairDisplay`
  - `mono`: `GoogleFonts.jetBrainsMono`
  - Offline testing safety: `DesignSystem.disableGoogleFontsInTests` prevents network lockups.

### 4.2 Typographic Hierarchy & Scale Factors
- `scale_small` (0.9x): Compact density for high-information reading.
- `scale_default` (1.0x): Standard baseline layout.
- `scale_large` (1.15x): Enhanced legibility.
- `scale_extra_large` (1.3x): Accessibility-first viewing.
- Line Spacing: Normal (1.5) and Relaxed (1.8).

---

## 5. Persistent User Preferences Architecture

### 5.1 Unified Preference Model
Both Web and Mobile store and validate the identical schema:
```json
{
  "themeMode": "light" | "dark" | "system",
  "colorPalette": "editorial" | "lavender" | "sage" | "powder_blue" | "peach" | "rose",
  "fontFamily": "serif" | "sans" | "mono",
  "fontScale": 0.9 | 1.0 | 1.15 | 1.3,
  "lineSpacing": "normal" | "relaxed",
  "highContrast": false,
  "reducedMotion": false,
  "language": "en" | "tr" | "de",
  "density": "comfortable" | "compact"
}
```

### 5.2 Zero-FOUC Web Implementation
- An inline script in `<head>` reads `localStorage` before paint and applies attributes to `document.documentElement` (`data-theme`, `data-palette`, `data-font`, `data-scale`, `data-contrast`, `data-spacing`, `data-motion`, `lang`).
- React `PreferencesProvider` provides reactive state, system media-query subscriptions, and live updates.
- Robust corruption recovery: any invalid or unparsable JSON falls back gracefully to `DEFAULT_PREFERENCES`.

### 5.3 Mobile Flutter Implementation
- `ThemeProvider` persists preferences to `SharedPreferences` with safe try/catch error handling.
- `LanguageProvider` manages `assets/lang/{locale}.json` with 100% key parity (233 keys across `en.json`, `tr.json`, `de.json`).

---

## 6. Accessibility & Motion Quality

- **Focus Visibility:** All interactive elements feature high-contrast `:focus-visible` rings (`outline: 2px solid var(--primary); outline-offset: 2px;`).
- **High Contrast Mode:** Distinct borders (`#ffffff` on dark, `#000000` on light) and maximized text contrast exceeding WCAG AAA standards.
- **Reduced Motion:** All animations collapse to 0.001ms when OS preference or in-app preference is enabled.
- **Screen Reader Support:** Semantic HTML elements, `aria-label` tags, and a prominent keyboard skip-link (`.skip-link`).
- **Book Cover Standardization:** Fixed 2:3 aspect ratio (`padding-top: 150%`) with `BookCoverFallback` component ensuring zero layout shifts.
