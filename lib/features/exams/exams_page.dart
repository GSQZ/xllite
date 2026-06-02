import 'package:flutter/material.dart';

import '../../api/xjit_features.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class ExamsPage extends StatelessWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureDataPage(
      title: '考试安排',
      feature: XjitFeature.exams,
      emptyTitle: '暂时没有考试数据',
      validator: (data) => data['exams'] is List,
      builder: (context, data) {
        final exams = mapList(data['exams']);
        if (exams.isEmpty) {
          return const EmptyPanel(
            title: '暂无考试安排',
            subtitle: '有考试数据后会显示时间和地点。',
            icon: Icons.event_available_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: exams.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _ExamCard(exam: exams[index]);
          },
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final Map<String, dynamic> exam;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = textValue(exam['courseName'], fallback: '未命名考试');
    final time = textValue(exam['examTime'], fallback: '');
    final place = textValue(exam['examPlace'], fallback: '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ExamMeta(icon: Icons.schedule_outlined, text: time),
                  ],
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _ExamMeta(icon: Icons.place_outlined, text: place),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamMeta extends StatelessWidget {
  const _ExamMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
