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
            subtitle: '有考试数据后会显示时间、地点和座位号。',
            icon: Icons.event_available_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: exams.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = exams[index];
            return InfoCard(
              icon: Icons.event_note_outlined,
              title: textValue(item['courseName'], fallback: '未命名考试'),
              subtitle:
                  '${textValue(item['examTime'])}\n${textValue(item['examPlace'])} · 座位 ${textValue(item['seatNo'])}',
              trailing: Text(textValue(item['campus'])),
            );
          },
        );
      },
    );
  }
}
