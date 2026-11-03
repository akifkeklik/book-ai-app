'use client';

import React, { createContext, useContext, useEffect, useState, useTransition, useCallback } from 'react';
import {
  type LibrisPreferences,
  type ThemeMode,
  type ColorPalette,
  type FontFamily,
  type FontScale,
  type LineSpacing,
  type Language,
  type Density,
  DEFAULT_PREFERENCES,
  loadPreferences,
  savePreferences,
  applyPreferencesToDom,
} from '@/lib/preferences';
import { translate, type TranslationKey } from '@/lib/i18n';

interface PreferencesContextValue {
  preferences: LibrisPreferences;
  setThemeMode: (mode: ThemeMode) => void;
  setColorPalette: (palette: ColorPalette) => void;
  setFontFamily: (font: FontFamily) => void;
  setFontScale: (scale: FontScale) => void;
  setLineSpacing: (spacing: LineSpacing) => void;
  setHighContrast: (hc: boolean) => void;
  setReducedMotion: (rm: boolean) => void;
  setLanguage: (lang: Language) => void;
  setDensity: (density: Density) => void;
  resetToDefaults: () => void;
  t: (key: TranslationKey, args?: Record<string, string | number>) => string;
}

const PreferencesContext = createContext<PreferencesContextValue | null>(null);

export function PreferencesProvider({ children }: { children: React.ReactNode }) {
  // Lazy state initialization prevents setState in effect
  const [preferences, setPreferences] = useState<LibrisPreferences>(() => {
    if (typeof window !== 'undefined') {
      return loadPreferences();
    }
    return DEFAULT_PREFERENCES;
  });

  const [, startTransition] = useTransition();

  // Synchronize DOM attributes and listen to OS system dark/light changes
  useEffect(() => {
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    applyPreferencesToDom(preferences, mql.matches);

    const handleSystemChange = (e: MediaQueryListEvent) => {
      setPreferences((prev) => {
        if (prev.themeMode === 'system') {
          applyPreferencesToDom(prev, e.matches);
        }
        return prev;
      });
    };

    mql.addEventListener('change', handleSystemChange);
    return () => mql.removeEventListener('change', handleSystemChange);
  }, [preferences]);

  const updatePreferences = useCallback((updater: (prev: LibrisPreferences) => LibrisPreferences) => {
    startTransition(() => {
      setPreferences((prev) => {
        const next = updater(prev);
        savePreferences(next);
        const systemIsDark = typeof window !== 'undefined'
          ? window.matchMedia('(prefers-color-scheme: dark)').matches
          : true;
        applyPreferencesToDom(next, systemIsDark);
        return next;
      });
    });
  }, []);

  const setThemeMode = useCallback((mode: ThemeMode) => {
    updatePreferences((prev) => ({ ...prev, themeMode: mode }));
  }, [updatePreferences]);

  const setColorPalette = useCallback((colorPalette: ColorPalette) => {
    updatePreferences((prev) => ({ ...prev, colorPalette }));
  }, [updatePreferences]);

  const setFontFamily = useCallback((fontFamily: FontFamily) => {
    updatePreferences((prev) => ({ ...prev, fontFamily }));
  }, [updatePreferences]);

  const setFontScale = useCallback((fontScale: FontScale) => {
    updatePreferences((prev) => ({ ...prev, fontScale }));
  }, [updatePreferences]);

  const setLineSpacing = useCallback((lineSpacing: LineSpacing) => {
    updatePreferences((prev) => ({ ...prev, lineSpacing }));
  }, [updatePreferences]);

  const setHighContrast = useCallback((highContrast: boolean) => {
    updatePreferences((prev) => ({ ...prev, highContrast }));
  }, [updatePreferences]);

  const setReducedMotion = useCallback((reducedMotion: boolean) => {
    updatePreferences((prev) => ({ ...prev, reducedMotion }));
  }, [updatePreferences]);

  const setLanguage = useCallback((language: Language) => {
    updatePreferences((prev) => ({ ...prev, language }));
  }, [updatePreferences]);

  const setDensity = useCallback((density: Density) => {
    updatePreferences((prev) => ({ ...prev, density }));
  }, [updatePreferences]);

  const resetToDefaults = useCallback(() => {
    updatePreferences(() => ({ ...DEFAULT_PREFERENCES }));
  }, [updatePreferences]);

  const t = useCallback((key: TranslationKey, args?: Record<string, string | number>) => {
    return translate(preferences.language, key, args);
  }, [preferences.language]);

  return (
    <PreferencesContext.Provider
      value={{
        preferences,
        setThemeMode,
        setColorPalette,
        setFontFamily,
        setFontScale,
        setLineSpacing,
        setHighContrast,
        setReducedMotion,
        setLanguage,
        setDensity,
        resetToDefaults,
        t,
      }}
    >
      {children}
    </PreferencesContext.Provider>
  );
}

export function usePreferences() {
  const ctx = useContext(PreferencesContext);
  if (!ctx) {
    return {
      preferences: DEFAULT_PREFERENCES,
      setThemeMode: () => {},
      setColorPalette: () => {},
      setFontFamily: () => {},
      setFontScale: () => {},
      setLineSpacing: () => {},
      setHighContrast: () => {},
      setReducedMotion: () => {},
      setLanguage: () => {},
      setDensity: () => {},
      resetToDefaults: () => {},
      t: (key: TranslationKey, args?: Record<string, string | number>) => translate('en', key, args),
    };
  }
  return ctx;
}
