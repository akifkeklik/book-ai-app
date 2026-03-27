import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        context.read<FavoritesProvider>().loadFavorites(auth.currentUser!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final favs = context.watch<FavoritesProvider>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Books')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_outline,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                const SizedBox(height: 20),
                Text('Your Reading List',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  'Sign in to save books and keep track of your reading list',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Sign In'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Books'),
        actions: [
          if (favs.favorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${favs.favorites.length}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => favs.loadFavorites(auth.currentUser!.id),
        child: _buildBody(auth, favs),
      ),
    );
  }

  Widget _buildBody(AuthProvider auth, FavoritesProvider favs) {
    if (favs.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (favs.favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_outline,
                  size: 80,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.5)),
              const SizedBox(height: 20),
              Text('No saved books yet',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                'Tap the bookmark icon on any book to save it here',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Discover Books'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: favs.favorites.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 104),
      itemBuilder: (context, i) {
        final fav = favs.favorites[i];
        return Dismissible(
          key: ValueKey(fav.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Colors.red.withOpacity(0.8),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, color: Colors.white),
                SizedBox(height: 4),
                Text('Remove',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove Favorite'),
                content: Text('Remove "${fav.bookTitle}" from favorites?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Remove',
                          style: TextStyle(color: Colors.red))),
                ],
              ),
            );
          },
          onDismissed: (_) {
            favs.removeFavoriteByIsbn(
              userId: auth.currentUser!.id,
              isbn13: fav.isbn13,
            );
          },
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: fav.thumbnail.isNotEmpty
                    ? fav.thumbnail
                    : 'https://via.placeholder.com/56x80.png?text=Book',
                width: 56,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    width: 56,
                    height: 80,
                    color: Theme.of(context).colorScheme.surface),
                errorWidget: (_, __, ___) => Container(
                    width: 56,
                    height: 80,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Icon(Icons.menu_book_rounded, size: 24)),
              ),
            ),
            title: Text(
              fav.bookTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Saved ${_formatDate(fav.addedAt)}',
                style:
                    Theme.of(context).textTheme.bodySmall,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/book/${fav.isbn13}'),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${dt.day}/${dt.month}/${dt.year}';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'just now';
  }
}
