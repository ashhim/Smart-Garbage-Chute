import 'package:flutter/material.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analytics', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),

          // Alerts by Severity
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alerts by Severity (24h)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _buildBarItem('High', 12, Colors.red),
                  _buildBarItem('Medium', 8, Colors.orange),
                  _buildBarItem('Low', 5, Colors.blue),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Top Alert Categories
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Alert Categories',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _buildCategory('Blockage', 24),
                  _buildCategory('Overflow', 15),
                  _buildCategory('Leak Detection', 12),
                  _buildCategory('Door Open', 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarItem(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text('$count')],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: count / 12,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(String name, int count) {
    return ListTile(
      title: Text(name),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$count'),
      ),
    );
  }
}
