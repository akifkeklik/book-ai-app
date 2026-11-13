import type { Metadata } from "next";
import "./globals.css";
import { cookies } from "next/headers";
import { translate } from "@/lib/i18n";
import { resolveLanguage } from "@/lib/preferences";
import { AuthProvider } from "@/components/AuthProvider";
import { PreferencesProvider } from "@/components/PreferencesProvider";
import { Navbar } from "@/components/Navbar";
import { SpotlightSearch } from "@/components/SpotlightSearch";

export const metadata: Metadata = {
  title: "Libris | Book Discovery & Personal Learning",
  description: "Personalized book discovery, reading tracker, and intellectual library powered by hybrid AI.",
  manifest: "/manifest.json",
};

const themeInitScript = `
(function() {
  try {
    var raw = localStorage.getItem('libris_user_preferences');
    var theme = 'dark';
    var palette = 'ocean_blue';
    var font = 'serif';
    var scale = '1.0';
    var spacing = 'normal';
    var contrast = 'false';
    var motion = 'normal';
    var density = 'comfortable';
    var lang = 'en';

    if (raw) {
      var p = JSON.parse(raw);
      if (p.themeMode === 'light') theme = 'light';
      else if (p.themeMode === 'system') {
        theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      }
      if (p.colorPalette) palette = p.colorPalette;
      if (p.fontFamily) font = p.fontFamily;
      if (p.fontScale) scale = String(p.fontScale);
      if (p.lineSpacing) spacing = p.lineSpacing;
      if (p.highContrast) contrast = 'true';
      if (p.reducedMotion) motion = 'reduced';
      if (p.density) density = p.density;
      if (p.language) lang = p.language;
    } else {
      theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }

    var doc = document.documentElement;
    doc.setAttribute('data-theme', theme);
    doc.setAttribute('data-palette', palette);
    doc.setAttribute('data-font', font);
    doc.setAttribute('data-scale', scale);
    doc.setAttribute('data-spacing', spacing);
    doc.setAttribute('data-contrast', contrast);
    doc.setAttribute('data-motion', motion);
    doc.setAttribute('data-density', density);
    doc.setAttribute('lang', lang);
  } catch (e) {}
})();
`;

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const lang = resolveLanguage((await cookies()).get("libris_lang")?.value);
  return (
    <html lang={lang} suppressHydrationWarning>
      <head>
        <link rel="manifest" href="/manifest.json" />
        <meta name="theme-color" content="#0f172a" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
      </head>
      <body>
        <a href="#main-content" className="skip-link">{translate(lang, "skip_content")}</a>
        <PreferencesProvider>
          <AuthProvider>
            <SpotlightSearch />
            <Navbar />
            <main id="main-content" className="main-content">
              {children}
            </main>
          </AuthProvider>
        </PreferencesProvider>
      </body>
    </html>
  );
}
