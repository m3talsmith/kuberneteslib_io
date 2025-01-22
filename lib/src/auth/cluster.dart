import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:kuberneteslib/src/cluster/cluster.dart' as clusterlib;
import 'package:kuberneteslib/src/cluster/config.dart' as configlib;
import 'package:kuberneteslib/src/cluster/user.dart' as userlib;
import 'package:kuberneteslib/src/helpers/uint8list_converter.dart';
import 'bearer_client.dart';
import 'cert_client.dart';
part 'cluster.g.dart';

/// [ClusterAuth] is a core class for Kubernetes API authentication. It handles
/// authentication to the Kubernetes API calls and acts as an HTTP client wrapper.
///
/// The class supports two authentication methods:
/// 1. Token-based authentication (Bearer tokens)
/// 2. Certificate-based authentication (Client certificates)
///
/// It can be initialized from a Kubernetes configuration and automatically handles
/// token execution and renewal for supported platforms (Linux, macOS, Windows).
///
/// Example Usage:
///
/// ```dart
/// main() async {
///   final config = Config.fromYaml('<kubernetes cluster yaml>');
///   final auth = ClusterAuth.fromConfig(config);
///   await auth.ensureInitialization();
///
///   // Make authenticated requests
///   final response = await auth.get(Uri.parse('https://api.example.com/v1/pods'));
/// }
/// ```
@JsonSerializable()
class ClusterAuth extends http.BaseClient {
  ClusterAuth({required cluster});

  /// The cluster configuration containing server and certificate information
  @JsonKey(includeIfNull: false)
  clusterlib.Cluster? cluster;

  /// The user configuration containing authentication details
  @JsonKey(includeIfNull: false)
  userlib.User? user;

  /// Bearer token for token-based authentication
  @JsonKey(includeIfNull: false)
  String? token;

  /// Expiration timestamp for the bearer token
  @JsonKey(includeIfNull: false)
  DateTime? expirationTimestamp;

  /// Certificate authority data for validating the server's certificate
  @JsonKey(includeIfNull: false)
  @Uint8ListConverter()
  Uint8List? clientCertificateAuthority;

  /// Client certificate data for certificate-based authentication
  @JsonKey(includeIfNull: false)
  @Uint8ListConverter()
  Uint8List? clientCertificateData;

  /// Client private key data for certificate-based authentication
  @JsonKey(includeIfNull: false)
  @Uint8ListConverter()
  Uint8List? clientKeyData;

  /// Creates a new [ClusterAuth] instance from a Kubernetes [Config].
  ///
  /// Extracts and decodes the necessary certificate and authentication data from the config.
  /// This includes certificate authority data, client certificates, and private keys.
  ClusterAuth.fromConfig(configlib.Config config) {
    final context = config.contexts.firstWhere(
        (e) => (e.name != null && e.name == config.currentContext),
        orElse: () => config.contexts.first);
    cluster = config.clusters.firstWhere(
        (e) => (e.name != null && e.name == context.cluster),
        orElse: () => config.clusters.first);
    user = config.users.firstWhere(
        (e) => (e.name != null && e.name == context.user),
        orElse: () => config.users.first);

    clientCertificateAuthority =
        base64Decode(cluster?.certificateAuthorityData ?? '');
    clientCertificateData = base64Decode(user?.clientCertificateData ?? '');
    clientKeyData = base64Decode(user?.clientKeyData ?? '');
  }

  ClusterAuth.fromSelectedContext(configlib.Config config, String contextName) {
    final context = config.contexts.firstWhere(
        (e) => (e.name != null && e.name == contextName),
        orElse: () => config.contexts.first);
    cluster = config.clusters.firstWhere(
        (e) => (e.name != null && e.name == context.cluster),
        orElse: () => config.clusters.first);
    user = config.users.firstWhere(
        (e) => (e.name != null && e.name == context.user),
        orElse: () => config.users.first);

    clientCertificateAuthority =
        base64Decode(cluster?.certificateAuthorityData ?? '');
    clientCertificateData = base64Decode(user?.clientCertificateData ?? '');
    clientKeyData = base64Decode(user?.clientKeyData ?? '');
  }

  factory ClusterAuth.fromJson(Map<String, dynamic> json) =>
      _$ClusterAuthFromJson(json);

  Map<String, dynamic> toJson() => _$ClusterAuthToJson(this);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['User-Agent'] = 'kuberneteslib';

    if (token != null) {
      final options = BearerClient().sendOptions(
          token: token!, badCertificateCallback: (_, __, ___) => true);
      options['headers'].forEach((key, value) {
        request.headers[key] = value;
      });

      final securityContext = options['context'];
      final certificateCallback = options['badCertificateCallback'];

      final client = HttpClient(context: securityContext)
        ..badCertificateCallback = certificateCallback;

      return IOClient(client).send(request);
    }

    final options = CertClient().sendOptions(
        clientCertificateAuthority: clientCertificateAuthority!,
        clientCertificateData: clientCertificateData!,
        clientKeyData: clientKeyData!,
        badCertificateCallback: (_, __, ___) => true);

    options['headers'].forEach((key, value) {
      request.headers[key] = value;
    });

    var context = SecurityContext()..allowLegacyUnsafeRenegotiation = true;
    var client = HttpClient(context: context)
      ..badCertificateCallback = options['badCertificateCallback'];

    return IOClient(client).send(request);
  }
}
