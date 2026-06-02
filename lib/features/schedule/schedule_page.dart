import 'package:flutter/material.dart';

import '../../api/xjit_features.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureDataPage(
      title: '课表',
      feature: XjitFeature.schedule,
      emptyTitle: '暂时没有课表数据',
      validator: (data) => data['courses'] is List,
      builder: (context, data) {
        final courses = mapList(data['courses']);
        if (courses.isEmpty) {
          return const EmptyPanel(title: '当前学期没有课程');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: courses.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return InfoCard(
                icon: Icons.calendar_today_outlined,
                title: textValue(data['term'], fallback: '当前学期'),
                subtitle: '共 ${courses.length} 条课程记录',
              );
            }
            final item = courses[index - 1];
            return InfoCard(
              icon: Icons.menu_book_outlined,
              title: textValue(item['title'], fallback: '未命名课程'),
              subtitle:
                  '${textValue(item['day'])} ${textValue(item['sections'])}\n${textValue(item['teacher'])} · ${textValue(item['location'])}',
              trailing: Text(textValue(item['weeks'])),
            );
          },
        );
      },
    );
  }
}
