class ServerConfiguration {
  final String? build;
  final int? maxFileUploadSize;
  final int? maxMessageSize;
  final int? maxSubscriberCount;
  final int? maxTagCount;
  final int? maxTagLength;
  final int? minTagLength;
  final String? ver;
  final List<IceServer>? iceServers;

  ServerConfiguration({
    this.build,
    this.maxFileUploadSize,
    this.maxMessageSize,
    this.maxSubscriberCount,
    this.maxTagCount,
    this.maxTagLength,
    this.minTagLength,
    this.ver,
    this.iceServers,
  });
}

class IceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  IceServer.fromJson(Map<String, dynamic> json)
      : urls = List<String>.from(json['urls']),
        username = json['username'] as String?,
        credential = json['credential'] as String?;
}
