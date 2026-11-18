import '../../services/debug_log_service.dart';

typedef PlayerDebugLog = void Function(
  String event, {
  DebugLogCategory category,
  String? message,
  Map<String, Object?> details,
  String? Function()? messageBuilder,
  Map<String, Object?> Function()? detailsBuilder,
  DebugSeverity severity,
});
