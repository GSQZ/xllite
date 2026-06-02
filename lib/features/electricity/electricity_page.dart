import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class ElectricityPage extends ConsumerStatefulWidget {
  const ElectricityPage({super.key});

  @override
  ConsumerState<ElectricityPage> createState() => _ElectricityPageState();
}

class _ElectricityPageState extends ConsumerState<ElectricityPage> {
  static const _roomKey = 'last_room_query';

  final _roomController = TextEditingController();
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _restoreRoom();
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _restoreRoom() async {
    final storage = ref.read(secureStorageProvider);
    final room = await storage.read(key: _roomKey);
    if (!mounted || room == null || room.isEmpty) {
      return;
    }
    _roomController.text = room;
    setState(() => _future = _load(room));
  }

  Future<Map<String, dynamic>> _load(String room) async {
    final session = ref.read(authControllerProvider).when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    if (session == null) {
      throw const XjitApiException('请先登录');
    }
    final cleanRoom = room.trim();
    if (cleanRoom.isEmpty) {
      throw const XjitApiException('请输入宿舍号，例如 9#312');
    }
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _roomKey, value: cleanRoom);

    return ref.read(xjitApiClientProvider).run(
          XjitFeature.electricityAccount,
          username: session.username,
          password: session.password,
          params: {'roomQuery': cleanRoom},
        );
  }

  Future<void> _query() async {
    setState(() => _future = _load(_roomController.text));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('宿舍电费')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _roomController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _query(),
            decoration: const InputDecoration(
              labelText: '宿舍号',
              hintText: '例如 9#312',
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _query,
              icon: const Icon(Icons.bolt),
              label: const Text('查询剩余电量'),
            ),
          ),
          const SizedBox(height: 18),
          if (_future == null)
            const EmptyPanel(
              title: '输入宿舍号后查询',
              subtitle: '支持 9#312、5号楼524 这类写法。',
              icon: Icons.bolt_outlined,
            )
          else
            FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingPanel();
                }
                if (snapshot.hasError) {
                  return ErrorPanel(error: snapshot.error!, onRetry: _query);
                }

                final data = snapshot.data ?? const <String, dynamic>{};
                final remaining = data['remainingElectricity'] is Map
                    ? Map<String, dynamic>.from(data['remainingElectricity'] as Map)
                    : const <String, dynamic>{};
                final room = data['room'] is Map
                    ? Map<String, dynamic>.from(data['room'] as Map)
                    : const <String, dynamic>{};
                final value = textValue(remaining['value']);

                if (value == '-') {
                  return const EmptyPanel(title: '没有查到电费数据');
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('剩余电量'),
                            const SizedBox(height: 8),
                            Text(
                              '$value ${textValue(remaining['unit'], fallback: '度')}',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InfoCard(
                      icon: Icons.apartment_outlined,
                      title: textValue(room['buildingName'], fallback: '宿舍'),
                      subtitle:
                          '${textValue(room['levelName'])} · ${textValue(room['roomName'])}',
                      trailing: Text(textValue(room['query'])),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
