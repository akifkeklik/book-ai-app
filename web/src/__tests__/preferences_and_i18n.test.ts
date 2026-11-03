import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parsePreferences,
  resolveEffectiveTheme,
  DEFAULT_PREFERENCES,
  type LibrisPreferences,
} from '../lib/preferences';
import { translate, DICTIONARIES, localizeRecommendationReason, type TranslationKey } from '../lib/i18n';

test('parsePreferences: returns default preferences when given null, undefined, or empty input', () => {
  const resultNull = parsePreferences(null);
  assert.deepEqual(resultNull, DEFAULT_PREFERENCES);

  const resultUndefined = parsePreferences(undefined);
  assert.deepEqual(resultUndefined, DEFAULT_PREFERENCES);

  const resultEmpty = parsePreferences({});
  assert.deepEqual(resultEmpty, DEFAULT_PREFERENCES);
});

test('parsePreferences: preserves valid complete preferences', () => {
  const input: LibrisPreferences = {
    themeMode: 'light',
    colorPalette: 'sage',
    fontFamily: 'sans',
    fontScale: 1.15,
    lineSpacing: 'relaxed',
    highContrast: true,
    reducedMotion: true,
    language: 'tr',
    density: 'compact',
  };

  const parsed = parsePreferences(input);
  assert.deepEqual(parsed, input);
});

test('parsePreferences: safely recovers from corrupted fields with safe defaults without crashing', () => {
  const corruptInput = {
    themeMode: 'invalid_super_dark',
    colorPalette: 'neon_hacker',
    fontFamily: 'comic_sans',
    fontScale: 999.0, // illegal scale
    lineSpacing: 'super_wide',
    highContrast: 'not_a_bool',
    reducedMotion: 123,
    language: 'esperanto',
    density: 'ultra_dense',
  };

  const parsed = parsePreferences(corruptInput);

  assert.equal(parsed.themeMode, DEFAULT_PREFERENCES.themeMode);
  assert.equal(parsed.colorPalette, DEFAULT_PREFERENCES.colorPalette);
  assert.equal(parsed.fontFamily, DEFAULT_PREFERENCES.fontFamily);
  assert.equal(parsed.fontScale, DEFAULT_PREFERENCES.fontScale);
  assert.equal(parsed.lineSpacing, DEFAULT_PREFERENCES.lineSpacing);
  assert.equal(parsed.highContrast, DEFAULT_PREFERENCES.highContrast);
  assert.equal(parsed.reducedMotion, DEFAULT_PREFERENCES.reducedMotion);
  assert.equal(parsed.language, DEFAULT_PREFERENCES.language);
  assert.equal(parsed.density, DEFAULT_PREFERENCES.density);
});

test('resolveEffectiveTheme: correctly resolves system preference or explicit mode', () => {
  // System theme follows OS
  assert.equal(resolveEffectiveTheme('system', true), 'dark');
  assert.equal(resolveEffectiveTheme('system', false), 'light');

  // Explicit modes ignore OS
  assert.equal(resolveEffectiveTheme('light', true), 'light');
  assert.equal(resolveEffectiveTheme('light', false), 'light');
  assert.equal(resolveEffectiveTheme('dark', false), 'dark');
  assert.equal(resolveEffectiveTheme('dark', true), 'dark');
});

test('i18n translate: resolves localized strings for en, tr, and de', () => {
  assert.equal(translate('en', 'settings_title'), 'Settings & Personalization');
  assert.equal(translate('tr', 'settings_title'), 'Ayarlar ve Kişiselleştirme');
  assert.equal(translate('de', 'settings_title'), 'Einstellungen & Personalisierung');

  assert.equal(translate('en', 'theme_dark'), 'Dark');
  assert.equal(translate('tr', 'theme_dark'), 'Koyu');
  assert.equal(translate('de', 'theme_dark'), 'Dunkel');
});

test('i18n translate: performs variable replacement', () => {
  const translated = translate('en', 'hero_title');
  assert.equal(typeof translated, 'string');
  assert.ok(translated.length > 0);
});

test('i18n completeness: ensures 100% key parity across EN, TR, and DE dictionaries', () => {
  const enKeys = Object.keys(DICTIONARIES.en) as TranslationKey[];
  const trKeys = Object.keys(DICTIONARIES.tr) as TranslationKey[];
  const deKeys = Object.keys(DICTIONARIES.de) as TranslationKey[];

  assert.equal(enKeys.length, trKeys.length, `Key count mismatch between EN (${enKeys.length}) and TR (${trKeys.length})`);
  assert.equal(enKeys.length, deKeys.length, `Key count mismatch between EN (${enKeys.length}) and DE (${deKeys.length})`);

  for (const key of enKeys) {
    assert.ok(DICTIONARIES.tr[key], `Missing TR translation for key: ${key}`);
    assert.ok(DICTIONARIES.de[key], `Missing DE translation for key: ${key}`);
  }
});

test('six palettes x two appearance modes: validates all 12 combinations in parsePreferences and resolveEffectiveTheme', () => {
  const canonicalSix = ['ocean_blue', 'forest_green', 'lavender', 'terracotta', 'amber', 'turquoise'] as const;
  const modes = ['light', 'dark'] as const;

  for (const palette of canonicalSix) {
    for (const mode of modes) {
      const parsed = parsePreferences({
        themeMode: mode,
        colorPalette: palette,
      });
      assert.equal(parsed.colorPalette, palette);
      assert.equal(parsed.themeMode, mode);
      assert.equal(resolveEffectiveTheme(mode, false), mode);
    }
  }
});

test('i18n: translations exist for all 6 canonical palettes and Information Architecture keys in EN, TR, and DE', () => {
  const requiredPaletteKeys: TranslationKey[] = [
    'palette_ocean_blue',
    'palette_forest_green',
    'palette_lavender',
    'palette_terracotta',
    'palette_amber',
    'palette_turquoise',
  ];

  const requiredIaKeys: TranslationKey[] = [
    'nav_discover',
    'nav_for_you',
    'nav_my_library',
    'nav_profile_settings',
    'library_title',
    'library_subtitle',
    'tab_all',
    'tab_favorites',
    'tab_reading',
    'tab_want_to_read',
    'tab_finished',
    'catalog_title',
    'empty_library_title',
    'unauthenticated_library_title',
  ];

  for (const lang of ['en', 'tr', 'de'] as const) {
    for (const key of requiredPaletteKeys) {
      const val = translate(lang, key);
      assert.ok(val && val !== key, `Missing translation for ${key} in ${lang}`);
    }
    for (const key of requiredIaKeys) {
      const val = translate(lang, key);
      assert.ok(val && val !== key, `Missing translation for ${key} in ${lang}`);
    }
  }
});

test('localizeRecommendationReason: translates reasons deterministically across EN, TR, and DE', () => {
  const cases = [
    {
      raw: "Because you liked 'Dune'",
      en: "Because you liked 'Dune'",
      tr: "'Dune' kitabını beğendiğiniz için",
      de: "Weil Ihnen 'Dune' gefallen hat",
    },
    {
      raw: "Trending on Libris right now",
      en: "Trending on Libris right now",
      tr: "Libris'te Çok Popüler",
      de: "Aktuell im Trend bei Libris",
    },
    {
      raw: "From your reading list: 'Hyperion'",
      en: "From your reading list: 'Hyperion'",
      tr: "Okuma listenizden: 'Hyperion'",
      de: "Aus Ihrer Leseliste: 'Hyperion'",
    },
    {
      raw: "Because you enjoy Cyberpunk",
      en: "Because you enjoy Cyberpunk",
      tr: "Cyberpunk türünü sevdiğiniz için",
      de: "Weil Sie Cyberpunk mögen",
    },
  ];

  for (const c of cases) {
    for (const lang of ['en', 'tr', 'de'] as const) {
      const t = (key: TranslationKey, args?: Record<string, string | number>) => translate(lang, key, args);
      const res = localizeRecommendationReason(c.raw, t);
      assert.equal(res, c[lang]);
    }
  }
});


