class ConnectionOptions {
  final String host;
  final String apiKey;
  final int version;
  final bool? secure;

  ConnectionOptions(this.host, this.apiKey, this.version, {this.secure});
}
