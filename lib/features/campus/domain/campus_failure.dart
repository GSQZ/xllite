enum CampusFailureKind {
  validation,
  unauthenticated,
  forbidden,
  network,
  server,
  rejected,
  invalidResponse,
  cancelled,
  outcomeUnknown,
}

/// Safe UI error. Does not retain requests, tokens, payment passwords or HTML.
class CampusFailure implements Exception {
  const CampusFailure(this.kind, this.message, {this.operation});
  final CampusFailureKind kind;
  final String message;
  final String? operation;
  CampusFailure forOperation(String operation) =>
      CampusFailure(kind, message, operation: operation);
  @override
  String toString() => message;
}

CampusFailure campusFailure(Object error, String operation) =>
    error is CampusFailure
    ? error.forOperation(operation)
    : CampusFailure(
        CampusFailureKind.invalidResponse,
        '数据格式异常，请稍后重试',
        operation: operation,
      );

Never invalidData() => throw const CampusFailure(
  CampusFailureKind.invalidResponse,
  '服务器数据不完整，请稍后重试',
);

Never invalidInput(String message) =>
    throw CampusFailure(CampusFailureKind.validation, message);
