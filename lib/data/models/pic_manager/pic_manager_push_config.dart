import 'dart:core';

const picManagerSourceName = 'aaalice Nai Launcher';
const picManagerAdapter = 'aaalice-nai-launcher';

class PicManagerConfigException implements Exception {
  const PicManagerConfigException(this.reason);

  final PicManagerConfigFailure reason;
}

enum PicManagerConfigFailure { invalidUrl, insecureHttp }

class PicManagerEndpoint {
  const PicManagerEndpoint._(this.baseUri);

  static const String _assetsPath = '/api/v1/assets';
  final Uri baseUri;

  Uri get assetsUri => _appendPath(_assetsPath);
  Uri get sourcesUri => _appendPath('/api/v1/sources');
  String get normalizedBaseUrl => baseUri.toString();

  static PicManagerEndpoint parse(
    String value, {
    required bool allowInsecureHttp,
  }) {
    final raw = value.trim();
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        (parsed.scheme != 'https' && parsed.scheme != 'http') ||
        parsed.host.isEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty) {
      throw const PicManagerConfigException(PicManagerConfigFailure.invalidUrl);
    }
    if (parsed.scheme == 'http' && !allowInsecureHttp) {
      throw const PicManagerConfigException(
        PicManagerConfigFailure.insecureHttp,
      );
    }

    var path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith(_assetsPath)) {
      path = path.substring(0, path.length - _assetsPath.length);
    }
    path = path.replaceFirst(RegExp(r'/+$'), '');
    return PicManagerEndpoint._(parsed.replace(path: path));
  }

  Uri _appendPath(String suffix) {
    final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    return baseUri.replace(path: '$basePath$suffix');
  }
}

class PicManagerPushConfig {
  const PicManagerPushConfig({
    this.baseUrl = '',
    this.allowInsecureHttp = false,
    this.autoPushOnFavorite = false,
    this.hasToken = false,
  });

  final String baseUrl;
  final bool allowInsecureHttp;
  final bool autoPushOnFavorite;
  final bool hasToken;

  bool get isConfigured => baseUrl.isNotEmpty && hasToken;

  PicManagerEndpoint endpoint() =>
      PicManagerEndpoint.parse(baseUrl, allowInsecureHttp: allowInsecureHttp);

  PicManagerPushConfig copyWith({
    String? baseUrl,
    bool? allowInsecureHttp,
    bool? autoPushOnFavorite,
    bool? hasToken,
  }) => PicManagerPushConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
    autoPushOnFavorite: autoPushOnFavorite ?? this.autoPushOnFavorite,
    hasToken: hasToken ?? this.hasToken,
  );

  Map<String, Object> toStorage() => {
    'version': 1,
    'base_url': baseUrl,
    'allow_insecure_http': allowInsecureHttp,
    'auto_push_on_favorite': autoPushOnFavorite,
  };

  factory PicManagerPushConfig.fromStorage(Object? value) {
    if (value is! Map) return const PicManagerPushConfig();
    return PicManagerPushConfig(
      baseUrl: value['base_url'] is String
          ? (value['base_url'] as String).trim()
          : '',
      allowInsecureHttp: value['allow_insecure_http'] == true,
      autoPushOnFavorite: value['auto_push_on_favorite'] == true,
    );
  }
}

class PicManagerPushCredentials {
  const PicManagerPushCredentials({required this.config, required this.token});

  final PicManagerPushConfig config;
  final String token;
}
