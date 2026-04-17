import 'package:flutter/material.dart';
import '../constants/category_map.dart';
import '../widgets/category_card.dart';
import 'subcategory_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MOSCO Mobile'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              const Text(
                'Categories',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a category to continue browsing inventory',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFB0B0B0),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 28),
              // GridView with modern cards
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: categoryDbMap.keys.map((category) {
                  return CategoryCard(
                    category: category,
                    onTap: () {
                      debugPrint('[APP] Category selected: $category');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SubcategoryScreen(category: category),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
