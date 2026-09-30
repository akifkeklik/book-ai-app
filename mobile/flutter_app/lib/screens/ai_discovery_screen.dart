import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../domain/entities/book.dart';
import '../data/models/book_dto.dart';
import '../widgets/book_card.dart';
import '../providers/language_provider.dart';

class AiDiscoveryScreen extends StatefulWidget {
  const AiDiscoveryScreen({super.key});

  @override
  State<AiDiscoveryScreen> createState() => _AiDiscoveryScreenState();
}

class _AiDiscoveryScreenState extends State<AiDiscoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String _answer = "";
  List<Book> _referencedBooks = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitQuery() async {
    if (_isLoading) return;
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _answer = "";
      _referencedBooks = [];
    });

    try {
      final res = await ApiService.instance.chatWithAI(query);
      if (!mounted) return;
      setState(() {
        _answer = res['answer'] ?? context.tr('no_response');
        if (res['referenced_books'] != null) {
          _referencedBooks = (res['referenced_books'] as List)
              .map((b) => BookDto.fromJson(b as Map<String, dynamic>))
              .toList();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _answer = "${context.tr('error')}: $e";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ai_insight')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                if (_answer.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _answer,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                if (_referencedBooks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    context.tr('referenced_books'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _referencedBooks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 140,
                          child: BookCard(book: _referencedBooks[index]),
                        );
                      },
                    ),
                  ),
                ]
              ],
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: context.tr('search_hint'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitQuery(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _isLoading ? null : _submitQuery,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
