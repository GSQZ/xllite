import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import 'async_content.dart';

typedef FeatureDataBuilder =
    Widget Function(BuildContext context, Map<String, dynamic> data);

typedef FeatureDataValidator = bool Function(Map<String, dynamic> data);

class FeatureDataPage extends ConsumerStatefulWidget {
  const FeatureDataPage({
    super.key,
    required this.title,
    required this.feature,
    required this.builder,
    required this.emptyTitle,
    this.params = const {},
    this.validator,
  });

  final String title;
  final XjitFeature feature;
  final Map<String, dynamic> params;
  final FeatureDataBuilder builder;
  final FeatureDataValidator? validator;
  final String emptyTitle;

  @override
  ConsumerState<FeatureDataPage> createState() => _FeatureDataPageState();
}

class _FeatureDataPageState extends ConsumerState<FeatureDataPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load({bool forceRefresh = false}) async {
    final session = ref
        .read(authControllerProvider)
        .when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    if (session == null) {
      throw const XjitApiException('请先登录');
    }
    return ref
        .read(xjitApiCacheProvider)
        .run(
          widget.feature,
          username: session.username,
          password: session.password,
          params: widget.params,
          forceRefresh: forceRefresh,
        );
  }

  Future<void> _refresh() async {
    final future = _load(forceRefresh: true);
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder owns the visible error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel();
          }
          if (snapshot.hasError) {
            return ErrorPanel(error: snapshot.error!, onRetry: _refresh);
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final isValid = widget.validator?.call(data) ?? data.isNotEmpty;
          if (!isValid) {
            return EmptyPanel(title: widget.emptyTitle);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: widget.builder(context, data),
          );
        },
      ),
    );
  }
}

List<Map<String, dynamic>> mapList(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
  return const [];
}

String textValue(Object? value, {String fallback = '-'}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return fallback;
  }
  return text;
}
