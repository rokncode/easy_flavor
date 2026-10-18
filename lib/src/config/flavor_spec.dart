import 'package:meta/meta.dart';

/// Settings for a single flavor.
@immutable
class FlavorSpec {
  const FlavorSpec({
    required this.name,
    required this.appName,
    required this.androidId,
    required this.iosBundleId,
    this.firebaseProjectId,
  });

  /// Flavor name as used by Gradle, Xcode configurations and `--flavor`.
  final String name;

  /// User-visible app name (launcher label / CFBundleDisplayName).
  final String appName;
  final String androidId;
  final String iosBundleId;

  /// Firebase project for this flavor; only used when Firebase is enabled.
  final String? firebaseProjectId;

  FlavorSpec copyWith({
    String? appName,
    String? androidId,
    String? iosBundleId,
    String? firebaseProjectId,
  }) {
    return FlavorSpec(
      name: name,
      appName: appName ?? this.appName,
      androidId: androidId ?? this.androidId,
      iosBundleId: iosBundleId ?? this.iosBundleId,
      firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
    );
  }

  Map<String, Object?> toMap() => {
    'app_name': appName,
    'android_id': androidId,
    'ios_bundle_id': iosBundleId,
    if (firebaseProjectId != null) 'firebase_project': firebaseProjectId,
  };

  @override
  bool operator ==(Object other) =>
      other is FlavorSpec &&
      other.name == name &&
      other.appName == appName &&
      other.androidId == androidId &&
      other.iosBundleId == iosBundleId &&
      other.firebaseProjectId == firebaseProjectId;

  @override
  int get hashCode =>
      Object.hash(name, appName, androidId, iosBundleId, firebaseProjectId);

  @override
  String toString() => 'FlavorSpec($name, $appName, $androidId, $iosBundleId)';
}
