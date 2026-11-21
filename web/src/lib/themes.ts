/**
 * The ten Libris colour themes, one per hue family so no two look alike. Each has a light and a
 * dark variant; the CSS tokens for all twenty live in `src/app/themes.css`. This module holds what the JS side needs: the ids,
 * the picker swatches, and the migration of palette ids saved by earlier versions.
 */

export const THEME_IDS = [
  'cherry_red',
  'peach_blossom',
  'honey_gold',
  'sage_garden',
  'mint_breeze',
  'ocean_mist',
  'indigo_dusk',
  'lavender_dream',
  'rose_quartz',
  'graphite_slate',
] as const;

export type ThemeId = (typeof THEME_IDS)[number];

export const DEFAULT_THEME: ThemeId = 'ocean_mist';

/** Palette ids stored by earlier releases, mapped to the closest current theme. */
export const LEGACY_THEME_MAP: Record<string, ThemeId> = {
  // Earlier releases' palettes.
  ocean_blue: 'ocean_mist',
  powder_blue: 'ocean_mist',
  forest_green: 'mint_breeze',
  turquoise: 'mint_breeze',
  sage: 'sage_garden',
  lavender: 'lavender_dream',
  editorial: 'lavender_dream',
  terracotta: 'peach_blossom',
  peach: 'peach_blossom',
  amber: 'honey_gold',
  rose: 'rose_quartz',
  // Retired from the eight-theme set because they were near-duplicates of a sibling.
  vanilla_cream: 'honey_gold',
  arctic_sky: 'ocean_mist',
};

export function isThemeId(value: unknown): value is ThemeId {
  return typeof value === 'string' && (THEME_IDS as readonly string[]).includes(value);
}

/** Resolves a current or legacy palette id; anything else returns null. */
export function normalizeThemeId(value: unknown): ThemeId | null {
  if (isThemeId(value)) return value;
  if (typeof value === 'string' && Object.prototype.hasOwnProperty.call(LEGACY_THEME_MAP, value)) {
    return LEGACY_THEME_MAP[value];
  }
  return null;
}

export interface ThemeSwatch {
  /** Page background, surface and primary accent: what the picker previews. */
  bg: string;
  surface: string;
  primary: string;
  accent: string;
}

/** Must stay in sync with the matching blocks in themes.css (checked by a unit test). */
export const THEME_SWATCHES: Record<ThemeId, { light: ThemeSwatch; dark: ThemeSwatch }> = {
  cherry_red: {
    light: { bg: '#fef7f7', surface: '#ffffff', primary: '#c43e45', accent: '#f28b66' },
    dark: { bg: '#170c0c', surface: '#231515', primary: '#eb7675', accent: '#feb79e' },
  },
  peach_blossom: {
    light: { bg: '#fef7f4', surface: '#ffffff', primary: '#b05315', accent: '#dd9a5d' },
    dark: { bg: '#160d08', surface: '#221610', primary: '#da865a', accent: '#f3bf92' },
  },
  honey_gold: {
    light: { bg: '#fdf9f1', surface: '#ffffff', primary: '#8e6704', accent: '#d59f5e' },
    dark: { bg: '#140f06', surface: '#1f180d', primary: '#c19746', accent: '#ecc293' },
  },
  sage_garden: {
    light: { bg: '#f8faf3', surface: '#ffffff', primary: '#68751f', accent: '#92b880' },
    dark: { bg: '#0f1008', surface: '#191b11', primary: '#99a762', accent: '#b8d5aa' },
  },
  mint_breeze: {
    light: { bg: '#f3fbf9', surface: '#ffffff', primary: '#057c67', accent: '#61bdb7' },
    dark: { bg: '#08120f', surface: '#101c19', primary: '#57b29b', accent: '#98d9d4' },
  },
  ocean_mist: {
    light: { bg: '#f4fafe', surface: '#ffffff', primary: '#00769f', accent: '#59bbd0' },
    dark: { bg: '#071116', surface: '#0e1b22', primary: '#55a9d3', accent: '#93d7e7' },
  },
  indigo_dusk: {
    light: { bg: '#f7f9fe', surface: '#ffffff', primary: '#466ac7', accent: '#9ca2f5' },
    dark: { bg: '#0b0f19', surface: '#141926', primary: '#799bee', accent: '#c0c5ff' },
  },
  lavender_dream: {
    light: { bg: '#fbf7ff', surface: '#ffffff', primary: '#8959aa', accent: '#cf93cc' },
    dark: { bg: '#120d17', surface: '#1d1623', primary: '#b38bd2', accent: '#e7b9e5' },
  },
  rose_quartz: {
    light: { bg: '#fef7fa', surface: '#ffffff', primary: '#ae4b7c', accent: '#e78c9d' },
    dark: { bg: '#160c10', surface: '#22151a', primary: '#d67ea6', accent: '#fbb4c0' },
  },
  graphite_slate: {
    light: { bg: '#f7f9fd', surface: '#ffffff', primary: '#646e7c', accent: '#a3acb8' },
    dark: { bg: '#0d1014', surface: '#161a1f', primary: '#969fac', accent: '#c4cbd4' },
  },
};
