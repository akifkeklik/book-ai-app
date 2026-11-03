export type ThemeMode = 'light' | 'dark' | 'system';
export type ColorPalette =
  | 'ocean_blue'
  | 'forest_green'
  | 'lavender'
  | 'terracotta'
  | 'amber'
  | 'turquoise'
  | 'editorial'
  | 'sage'
  | 'powder_blue'
  | 'peach'
  | 'rose';
export type FontFamily = 'serif' | 'sans' | 'mono';
export type FontScale = 0.9 | 1.0 | 1.15 | 1.3;
export type LineSpacing = 'normal' | 'relaxed';
export type Language = 'en' | 'tr' | 'de';
export type Density = 'comfortable' | 'compact';

export interface LibrisPreferences {
  themeMode: ThemeMode;
  colorPalette: ColorPalette;
  fontFamily: FontFamily;
  fontScale: FontScale;
  lineSpacing: LineSpacing;
  highContrast: boolean;
  reducedMotion: boolean;
  language: Language;
  density: Density;
}

export const STORAGE_KEY = 'libris_user_preferences';

export const DEFAULT_PREFERENCES: LibrisPreferences = {
  themeMode: 'dark',
  colorPalette: 'ocean_blue',
  fontFamily: 'serif',
  fontScale: 1.0,
  lineSpacing: 'normal',
  highContrast: false,
  reducedMotion: false,
  language: 'en',
  density: 'comfortable',
};

const VALID_THEME_MODES: ThemeMode[] = ['light', 'dark', 'system'];
const VALID_PALETTES: ColorPalette[] = [
  'ocean_blue',
  'forest_green',
  'lavender',
  'terracotta',
  'amber',
  'turquoise',
  'editorial',
  'sage',
  'powder_blue',
  'peach',
  'rose',
];
const VALID_FONTS: FontFamily[] = ['serif', 'sans', 'mono'];
const VALID_SCALES: FontScale[] = [0.9, 1.0, 1.15, 1.3];
const VALID_SPACINGS: LineSpacing[] = ['normal', 'relaxed'];
const VALID_LANGUAGES: Language[] = ['en', 'tr', 'de'];
const VALID_DENSITIES: Density[] = ['comfortable', 'compact'];

/**
 * Validates and safely parses raw JSON or objects into a valid LibrisPreferences.
 * Corrupt or invalid fields are replaced with robust defaults without throwing.
 */
export function parsePreferences(raw: unknown): LibrisPreferences {
  if (!raw || typeof raw !== 'object') {
    return { ...DEFAULT_PREFERENCES };
  }

  const data = raw as Record<string, unknown>;

  const themeMode: ThemeMode = VALID_THEME_MODES.includes(data.themeMode as ThemeMode)
    ? (data.themeMode as ThemeMode)
    : DEFAULT_PREFERENCES.themeMode;

  const colorPalette: ColorPalette = VALID_PALETTES.includes(data.colorPalette as ColorPalette)
    ? (data.colorPalette as ColorPalette)
    : DEFAULT_PREFERENCES.colorPalette;

  const fontFamily: FontFamily = VALID_FONTS.includes(data.fontFamily as FontFamily)
    ? (data.fontFamily as FontFamily)
    : DEFAULT_PREFERENCES.fontFamily;

  const fontScale: FontScale = VALID_SCALES.includes(data.fontScale as FontScale)
    ? (data.fontScale as FontScale)
    : DEFAULT_PREFERENCES.fontScale;

  const lineSpacing: LineSpacing = VALID_SPACINGS.includes(data.lineSpacing as LineSpacing)
    ? (data.lineSpacing as LineSpacing)
    : DEFAULT_PREFERENCES.lineSpacing;

  const highContrast = typeof data.highContrast === 'boolean'
    ? data.highContrast
    : DEFAULT_PREFERENCES.highContrast;

  const reducedMotion = typeof data.reducedMotion === 'boolean'
    ? data.reducedMotion
    : DEFAULT_PREFERENCES.reducedMotion;

  const language: Language = VALID_LANGUAGES.includes(data.language as Language)
    ? (data.language as Language)
    : DEFAULT_PREFERENCES.language;

  const density: Density = VALID_DENSITIES.includes(data.density as Density)
    ? (data.density as Density)
    : DEFAULT_PREFERENCES.density;

  return {
    themeMode,
    colorPalette,
    fontFamily,
    fontScale,
    lineSpacing,
    highContrast,
    reducedMotion,
    language,
    density,
  };
}

/**
 * Safely loads preferences from localStorage or cookies in browser environments.
 */
export function loadPreferences(): LibrisPreferences {
  if (typeof window === 'undefined') {
    return { ...DEFAULT_PREFERENCES };
  }
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return parsePreferences(JSON.parse(raw));

    // Fallback: Read cookies for initial SSR hydration match
    if (typeof document !== 'undefined' && document.cookie) {
      const matchLang = document.cookie.match(/libris_lang=([^;]+)/);
      const matchTheme = document.cookie.match(/libris_theme=([^;]+)/);
      const matchPalette = document.cookie.match(/libris_palette=([^;]+)/);
      if (matchLang || matchTheme || matchPalette) {
        return parsePreferences({
          language: matchLang ? matchLang[1] : undefined,
          themeMode: matchTheme ? matchTheme[1] : undefined,
          colorPalette: matchPalette ? matchPalette[1] : undefined,
        });
      }
    }
    return { ...DEFAULT_PREFERENCES };
  } catch {
    return { ...DEFAULT_PREFERENCES };
  }
}

/**
 * Safely saves preferences to localStorage and sets client cookies for SSR synchronization.
 */
export function savePreferences(prefs: LibrisPreferences): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
    if (typeof document !== 'undefined') {
      document.cookie = `libris_lang=${prefs.language}; path=/; max-age=31536000; SameSite=Lax;`;
      document.cookie = `libris_theme=${prefs.themeMode}; path=/; max-age=31536000; SameSite=Lax;`;
      document.cookie = `libris_palette=${prefs.colorPalette}; path=/; max-age=31536000; SameSite=Lax;`;
    }
  } catch {
    // Ignore storage write quota exceptions gracefully
  }
}

/**
 * Resolves effective theme ('light' or 'dark') given mode and system preference.
 */
export function resolveEffectiveTheme(mode: ThemeMode, systemIsDark: boolean): 'dark' | 'light' {
  if (mode === 'system') {
    return systemIsDark ? 'dark' : 'light';
  }
  return mode;
}

/**
 * Applies preferences as data-* attributes on document.documentElement
 */
export function applyPreferencesToDom(prefs: LibrisPreferences, systemIsDark = true): void {
  if (typeof document === 'undefined') return;

  const root = document.documentElement;
  const effectiveTheme = resolveEffectiveTheme(prefs.themeMode, systemIsDark);

  root.setAttribute('data-theme', effectiveTheme);
  root.setAttribute('data-palette', prefs.colorPalette);
  root.setAttribute('data-font', prefs.fontFamily);
  root.setAttribute('data-scale', String(prefs.fontScale));
  root.setAttribute('data-spacing', prefs.lineSpacing);
  root.setAttribute('data-contrast', String(prefs.highContrast));
  root.setAttribute('data-motion', prefs.reducedMotion ? 'reduced' : 'normal');
  root.setAttribute('data-density', prefs.density);
  root.setAttribute('lang', prefs.language);
}
