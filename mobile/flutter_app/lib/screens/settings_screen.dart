import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recommendation_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/knowledge_graph_provider.dart';
import '../providers/learning_path_provider.dart';
import '../providers/learning_provider.dart';
import '../theme/design_system.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final lang = context.watch<LanguageProvider>();
    final auth = context.read<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Live Interactive Preview Card ─────────────────────────────────
          _buildLivePreviewCard(context, themeProvider, lang),
          const SizedBox(height: 24),

          // ── Appearance Section ────────────────────────────────────────────
          _buildSectionHeader(context, 'settings_appearance'),
          const SizedBox(height: 12),
          _buildSettingsCard(
            context,
            children: [
              // Theme Mode (Light / Dark / System)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.brightness_medium_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            context.tr('settings_theme_mode'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: context.tr('theme_light'),
                            icon: Icons.light_mode_outlined,
                            isSelected: themeProvider.themeMode == ThemeMode.light,
                            onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: context.tr('theme_dark'),
                            icon: Icons.dark_mode_outlined,
                            isSelected: themeProvider.themeMode == ThemeMode.dark,
                            onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: context.tr('theme_system'),
                            icon: Icons.settings_brightness_outlined,
                            isSelected: themeProvider.themeMode == ThemeMode.system,
                            onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),

              // 6 Pastel Palettes
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            context.tr('settings_color_palette'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: LibrisPalette.canonicalSix.map((pal) {
                        final isSelected = themeProvider.palette == pal;
                        return InkWell(
                          onTap: () => themeProvider.setPalette(pal),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? pal.primaryDark.withOpacity(0.18)
                                  : colorScheme.surfaceContainerHighest.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? pal.primaryDark : colorScheme.outline.withOpacity(0.12),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: pal.primaryDark,
                                    shape: BoxShape.circle,
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: pal.primaryDark.withOpacity(0.5), blurRadius: 4)]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    context.tr(pal.translationKey),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),

              // High Contrast Toggle
              SwitchListTile(
                title: Text(
                  context.tr('settings_high_contrast'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                secondary: Icon(Icons.contrast_outlined, color: colorScheme.primary),
                value: themeProvider.highContrast,
                onChanged: (val) => themeProvider.setHighContrast(val),
                activeColor: colorScheme.primary,
              ),

              Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),

              // Reduced Motion Toggle
              SwitchListTile(
                title: Text(
                  context.tr('settings_reduced_motion'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                secondary: Icon(Icons.motion_photos_off_outlined, color: colorScheme.primary),
                value: themeProvider.reducedMotion,
                onChanged: (val) => themeProvider.setReducedMotion(val),
                activeColor: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Readability Section ───────────────────────────────────────────
          _buildSectionHeader(context, 'settings_readability'),
          const SizedBox(height: 12),
          _buildSettingsCard(
            context,
            children: [
              // Font Family Selector
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.font_download_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            context.tr('settings_font_family'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: context.tr('font_sans'),
                            isSelected: themeProvider.fontFamily == 'editorial',
                            onTap: () => themeProvider.setFontFamily('editorial'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: context.tr('font_serif'),
                            isSelected: themeProvider.fontFamily == 'serif',
                            onTap: () => themeProvider.setFontFamily('serif'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildChoiceButton(
                            context: context,
                            label: 'Mono',
                            isSelected: themeProvider.fontFamily == 'mono',
                            onTap: () => themeProvider.setFontFamily('mono'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),

              // Text Scale (Font Size)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.format_size_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            context.tr('settings_text_size'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildScaleButton(context, themeProvider, 0.9, context.tr('scale_small')),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.0, context.tr('scale_default')),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.15, context.tr('scale_large')),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.3, context.tr('scale_extra_large')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),

              // Line Spacing
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.format_line_spacing_outlined, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              context.tr('settings_line_spacing'),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        _buildSmallPill(
                          label: context.tr('line_spacing_normal'),
                          isSelected: themeProvider.lineSpacing <= 1.05,
                          onTap: () => themeProvider.setLineSpacing(1.0),
                          context: context,
                        ),
                        const SizedBox(width: 8),
                        _buildSmallPill(
                          label: context.tr('line_spacing_relaxed'),
                          isSelected: themeProvider.lineSpacing > 1.05,
                          onTap: () => themeProvider.setLineSpacing(1.25),
                          context: context,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Language & Region Section ─────────────────────────────────────
          _buildSectionHeader(context, 'settings_language'),
          const SizedBox(height: 12),
          _buildSettingsCard(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.language, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              context.tr('language'),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        _LangButton(
                          label: 'TR',
                          isActive: lang.currentLanguageCode == 'tr',
                          onTap: () => lang.setLanguage('tr'),
                        ),
                        const SizedBox(width: 6),
                        _LangButton(
                          label: 'EN',
                          isActive: lang.currentLanguageCode == 'en',
                          onTap: () => lang.setLanguage('en'),
                        ),
                        const SizedBox(width: 6),
                        _LangButton(
                          label: 'DE',
                          isActive: lang.currentLanguageCode == 'de',
                          onTap: () => lang.setLanguage('de'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Profile & Account Section ─────────────────────────────────────
          _buildSectionHeader(context, 'settings_profile'),
          const SizedBox(height: 12),
          _buildSettingsCard(
            context,
            children: [
              if (auth.isLoggedIn) ...[
                ListTile(
                  leading: Icon(Icons.person_outline, color: colorScheme.primary),
                  title: Text(auth.currentUser?.email ?? 'User'),
                  subtitle: Text(context.tr('profile_auth_method')),
                ),
                Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),
                ListTile(
                  leading: Icon(Icons.auto_awesome, color: colorScheme.primary),
                  title: Text(context.tr('taste_profile')),
                  subtitle: Text(context.tr('select_genres_hint')),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/onboarding'),
                ),
                Divider(height: 1, color: colorScheme.outline.withOpacity(0.08)),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.orangeAccent),
                  title: Text(context.tr('logout')),
                  onTap: () async {
                    if (context.mounted) {
                      context.read<FavoritesProvider>().clearFavorites();
                      context.read<RecommendationProvider>().clearUserData();
                      context.read<NotesProvider>().clear();
                      context.read<KnowledgeGraphProvider>().updateUser(null);
                      context.read<LearningPathProvider>().updateUser(null);
                      context.read<LearningProvider>().updateUser(null);
                    }
                    await auth.logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(Icons.login_rounded, color: colorScheme.primary),
                  title: Text(context.tr('sign_in_hint')),
                  subtitle: Text(context.tr('sign_in_subtitle')),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/login'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 36),

          // ── Version Footer ────────────────────────────────────────────────
          Center(
            child: Text(
              'Libris v2.5.0 Editorial Experience',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Live Preview Card ─────────────────────────────────────────────────────
  Widget _buildLivePreviewCard(BuildContext context, ThemeProvider themeProvider, LanguageProvider lang) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: themeProvider.highContrast ? colorScheme.outline : colorScheme.outline.withOpacity(0.15),
          width: themeProvider.highContrast ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr('settings_live_preview'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DesignSystem.statusReading.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.tr('reading'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: DesignSystem.statusReading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('preview_book_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('preview_book_author'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '“${context.tr('preview_quote')}”',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurface.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String key) {
    return Text(
      context.tr(key).toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            fontSize: 11,
          ),
    );
  }

  Widget _buildSettingsCard(BuildContext context, {required List<Widget> children}) {
    final highContrast = context.watch<ThemeProvider>().highContrast;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.outline.withOpacity(0.1),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildChoiceButton({
    required BuildContext context,
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScaleButton(BuildContext context, ThemeProvider provider, double scale, String label) {
    final isSelected = (provider.textScaleFactor - scale).abs() < 0.05;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => provider.setTextScaleFactor(scale),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSmallPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.transparent : colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary : colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.transparent : colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
