import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/xjit_features.dart';
import '../../ui/xl_theme.dart';
import '../../ui/xl_widgets.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class GradesPage extends StatelessWidget {
  const GradesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureDataPage(
      title: '成绩',
      feature: XjitFeature.grades,
      emptyTitle: '暂时没有成绩数据',
      validator: (data) =>
          data['summary'] is Map ||
          data['normalGrades'] is List ||
          data['makeupGrades'] is List,
      builder: (context, data) {
        final summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : const <String, dynamic>{};
        final normalGrades = mapList(data['normalGrades']);
        final makeupGrades = mapList(data['makeupGrades']);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryGrid(summary: summary),
            const SizedBox(height: 16),
            _SectionTitle('正常成绩', normalGrades.length),
            const SizedBox(height: 10),
            if (normalGrades.isEmpty)
              const EmptyPanel(title: '没有正常成绩记录')
            else
              ...normalGrades.map(_GradeCard.new),
            const SizedBox(height: 16),
            _SectionTitle('补考/重修', makeupGrades.length),
            const SizedBox(height: 10),
            if (makeupGrades.isEmpty)
              const EmptyPanel(title: '没有补考或重修记录')
            else
              ...makeupGrades.map(_GradeCard.new),
          ],
        );
      },
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('课程数', textValue(summary['courseCount'], fallback: '0')),
      ('总学分', textValue(summary['totalCredits'], fallback: '0')),
      ('绩点', textValue(summary['weightedGradePoint'], fallback: '-')),
      ('未通过', textValue(summary['failedCourseCount'], fallback: '0')),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.9,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return XLCard(
          padding: const EdgeInsets.all(14),
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.$1,
                style: const TextStyle(
                  color: XLColors.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: XLColors.ink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text('$count 条'),
      ],
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard(this.item);

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        icon: LucideIcons.graduationCap,
        title: textValue(item['courseName'], fallback: '未命名课程'),
        subtitle:
            '${textValue(item['term'])} · ${textValue(item['credit'])} 学分\n${textValue(item['examNature'])}',
        trailing: Text(
          textValue(item['score']),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
