import 'package:flutter/material.dart';

/// Modern category card with icon, emoji, and red accent styling
class CategoryCard extends StatelessWidget {
  final String category;
  final VoidCallback onTap;
  final Map<String, Map<String, dynamic>> categoryEmojis = {
    'Oil Seals': {'icon': Icons.circle, 'emoji': '🔵'},
    'Monoseals': {'icon': Icons.radio_button_checked, 'emoji': '⭕'},
    'Wiper Seals': {'icon': Icons.blur_on, 'emoji': '🌊'},
    'Wipermono': {'icon': Icons.grain, 'emoji': '🎯'},
  };

  CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final emojiData = categoryEmojis[category] ?? {
      'icon': Icons.category,
      'emoji': '📦'
    };
    final icon = emojiData['icon'] as IconData;
    final emoji = emojiData['emoji'] as String;

    return Material(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border(
              top: BorderSide(
                color: const Color(0xFFE53935),
                width: 3,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 12),
              Icon(
                icon,
                size: 32,
                color: const Color(0xFFE53935),
              ),
              const SizedBox(height: 16),
              Text(
                category,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
