import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recommendation_provider.dart';
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
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionHeader(context, 'settings_appearance'),
          const SizedBox(height: 16),
          _buildSettingsCard(
            context,
            children: [
              _buildLanguageToggle(context, lang),
              Divider(color: Theme.of(context).colorScheme.outline.withOpacity(0.05)),

              // ── Dark/Light Mode Toggle (Senior Update) ──────────────────
              SwitchListTile(
                title: Text(context.tr('settings_dark_mode')),
                secondary: Icon(
                  themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: colorScheme.primary
                ),
                value: themeProvider.isDarkMode,
                onChanged: (val) {
                  themeProvider.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
                },
                activeColor: colorScheme.primary,
              ),

              Divider(color: Theme.of(context).colorScheme.outline.withOpacity(0.05)),

              // ── Color Theme Picker (Requested: Red, Blue, Green, Yellow, Purple)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('theme'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildColorDot(context, themeProvider, ThemeProvider.red),
                        _buildColorDot(context, themeProvider, ThemeProvider.blue),
                        _buildColorDot(context, themeProvider, ThemeProvider.green),
                        _buildColorDot(context, themeProvider, ThemeProvider.yellow),
                        _buildColorDot(context, themeProvider, ThemeProvider.purple),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(color: Theme.of(context).colorScheme.outline.withOpacity(0.05)),

              // ── Text Size Picker ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('settings_text_size') != 'settings_text_size' ? context.tr('settings_text_size') : 'Text Size',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildScaleButton(context, themeProvider, 0.9, 'Small'),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.0, 'Default'),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.15, 'Large'),
                          const SizedBox(width: 8),
                          _buildScaleButton(context, themeProvider, 1.3, 'Extra Large'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildSectionHeader(context, 'settings_profile'),
          const SizedBox(height: 16),
          _buildSettingsCard(
            context,
            children: [
              ListTile(
                leading: Icon(Icons.person_outline, color: colorScheme.primary),
                title: Text(auth.currentUser?.email ?? 'User'),
                subtitle: Text(context.tr('profile_auth_method')),
              ),
              Divider(color: Theme.of(context).colorScheme.outline.withOpacity(0.05)),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.orangeAccent),
                title: Text(context.tr('logout')),
                onTap: () async {
                  if (context.mounted) {
                    context.read<FavoritesProvider>().clearFavorites();
                    context.read<RecommendationProvider>().clearUserData();
                  }
                  await auth.logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
          const SizedBox(height: 48),
          Center(
            child: Text(
              'Libris v2.2.0 Premium',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  ),
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
            letterSpacing: 2,
          ),
    );
  }

  Widget _buildSettingsCard(BuildContext context, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildColorDot(BuildContext context, ThemeProvider provider, Color color) {
    final isSelected = provider.seedColor.value == color.value;
    return GestureDetector(
      onTap: () => provider.setSeedColor(color),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
              : [],
        ),
      ),
    );
  }

  Widget _buildScaleButton(BuildContext context, ThemeProvider provider, double scale, String label) {
    final isSelected = provider.textScaleFactor == scale;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => provider.setTextScaleFactor(scale),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : colorScheme.outline.withOpacity(0.1),
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

  Widget _buildLanguageToggle(BuildContext context, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Text(context.tr('language'), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          Row(
            children: [
              _LangButton(
                label: 'TR',
                isActive: lang.currentLanguageCode == 'tr',
                onTap: () => lang.setLanguage('tr'),
              ),
              const SizedBox(width: 8),
              _LangButton(
                label: 'EN',
                isActive: lang.currentLanguageCode == 'en',
                onTap: () => lang.setLanguage('en'),
              ),
            ],
          ),
        ],
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary : colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.transparent : colorScheme.outline.withOpacity(0.1),
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
