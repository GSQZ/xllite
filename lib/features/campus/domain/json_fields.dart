import 'campus_failure.dart';

typedef Json = Map<String, dynamic>;

Json objectValue(Object? value) {
  if (value is! Map<String, dynamic>) invalidData();
  return value;
}

String textValue(Object? value, {bool required = false}) {
  if (value == null && !required) return '';
  if (value is! String && value is! num) invalidData();
  final text = value.toString();
  if (required && text.trim().isEmpty) invalidData();
  return text;
}

List<T> listValue<T>(Object? value, T Function(Json) parse) {
  if (value is! List) invalidData();
  return List.unmodifiable(value.map((e) => parse(objectValue(e))));
}

int integerValue(Object? value) {
  final parsed = value is int ? value : int.tryParse(textValue(value));
  if (parsed == null) invalidData();
  return parsed;
}

double numberValue(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(textValue(value));
  if (parsed == null || !parsed.isFinite) invalidData();
  return parsed;
}

bool boolValue(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is! bool) invalidData();
  return value;
}

/// Scalar strings from school systems can be descriptive (e.g. 缓考/优秀).
/// Keep the original value instead of silently turning missing values into zero.
double? optionalNumber(String value) {
  final result = double.tryParse(value);
  return result != null && result.isFinite ? result : null;
}
