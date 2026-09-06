import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Embedded TLS 1.3 self-signed certificate and private key manager for local peer connections
class TlsCertificateManager {
  TlsCertificateManager._();

  static const String _defaultCertPem = '''
-----BEGIN CERTIFICATE-----
MIIDETCCAfmgAwIBAgIUM0iTzDaWFtORMFPLFLgrwfI2QSYwDQYJKoZIhvcNAQEL
BQAwGDEWMBQGA1UEAwwNRHJvcEZsb3cgUGVlcjAeFw0yNjA5MDYxODQwMDFaFw0z
NjA5MDMxODQwMDFaMBgxFjAUBgNVBAMMDURyb3BGbG93IFBlZXIwggEiMA0GCSqG
SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCOzRREyAsqrXDs7GtAJ6HMukFhlhdWrfne
pK2GsgStsTFOMEKiXvV1w+mJbIgq8EoSnLYB3BSG4PWmJRjQvJZ0de39EP9ZeAoi
mRLlQVVWerl/2Xa+kFXfNTAOygiQlVqpLkuGvzy6HFfOQ/nvq1Nft5Y7alt5eJxd
wYH17zMLmFJntLKEus1jgMurM7oMKpjfczDH32Ff6MAOAy8s9hcjMhLaW8fdZm/l
mIf7xLf6df6WvWaOgiW06+EGt6TRfNF2VcIFStzrZ0S0Pc9LKUXejZ6p+KHRGct3
e5S+e/smJWeemDTu3xwGqd4gtbh3WHGwhineiTaw9XhhBPfWYbEBAgMBAAGjUzBR
MB0GA1UdDgQWBBRdIpjUFtshXZVRl2pCayIT2HKV0zAfBgNVHSMEGDAWgBRdIpjU
FtshXZVRl2pCayIT2HKV0zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA
A4IBAQBUMK/aK1k4dxH4V3J3NDLd30/FYihsZcBLmFID4WTSVdJyQ/OUVBzxMdC+
X4NNX1mG6Dpov8D63NyE6W9+FGkt26AcgrgObUu5sYELsLcbcZ6eCwtyc9FWFrD8
L9TH12xp2ZVvA8EtoPiwTTmpll4WZ1iRNkwtIr0NAw1EzQDdp7MwFqIqRzFbWxVH
ir4/t4GyaUzMb4Y3JCCRVre9LBwFLafQfMquA2QlNEiaOY+omNGvDJ3RIRoaTeiv
wl7Zp3JqqzwFr3TOsBWCU6iN6X7IqD+r2tWRIOqdTP78AnE0nZOytULU/weq1leW
jWZNVp0W03NbjgH5Fx9iMzV/ua35
-----END CERTIFICATE-----
''';

  static const String _defaultKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCOzRREyAsqrXDs
7GtAJ6HMukFhlhdWrfnepK2GsgStsTFOMEKiXvV1w+mJbIgq8EoSnLYB3BSG4PWm
JRjQvJZ0de39EP9ZeAoimRLlQVVWerl/2Xa+kFXfNTAOygiQlVqpLkuGvzy6HFfO
Q/nvq1Nft5Y7alt5eJxdwYH17zMLmFJntLKEus1jgMurM7oMKpjfczDH32Ff6MAO
Ay8s9hcjMhLaW8fdZm/lmIf7xLf6df6WvWaOgiW06+EGt6TRfNF2VcIFStzrZ0S0
Pc9LKUXejZ6p+KHRGct3e5S+e/smJWeemDTu3xwGqd4gtbh3WHGwhineiTaw9Xhh
BPfWYbEBAgMBAAECggEABDRA+t/y0uFDc/BWUKk+TmIgupLdRisd7fJVI4IBuOvE
62es7O/W9Ba5xbS86niSnsTKRYElCjraqAgvoPGWi/fMt3Nfjn2XITJc9tD25C4w
19LWzUk/rnz34TPZ05E102MQkKH4OgVC/wzURu+B0fgm7ihoio3vXvlAw6yjoqXg
jdr9yqCvToN8VP0UvUW+kET+rKV2CgnYgBSQDaRTWVjNJFdXNB7VIg4ZHjWrq1sm
n9oOFePMhrtUTxZOFAOh10z1IOd/X5RveawUWhGz/G1HeeankLbWv6+i1axa5Suq
PMKJQfj5UhzFCsfpJIdFiUm0cDWI8TXgcjD+KHcpCwKBgQDAfcSUOT6xwFVFQY3q
eAgdaQs70OmpN3p2hMORgkESpalgGDIE8oMBR+zW1kY/RDts95vWPxPDLp4FWF+D
u3Zioj34uizWwYF6YXbvdzFafyRI5z6MCOeaHoDhfvMThO5lZlw50waTno9+UVDF
yDDHymDLZulRK7iJe2OpOwsIRwKBgQC96l6pi8JCy9sHrua5R/ShsxCRK2Uv3PoU
ZxDZnbmNUc3pK34NahuAJ1LTVUCEOZyXkLzm9ocguCrTKAHCGw6KkVz5zoxNkkbl
oNAUSKZqLCFZud02+ofKXIGXGc0yGbZtEJILagbBabAIHT/MaMUbsAPs5iJUMWBc
SKdppfxodwKBgQCHCDMcn8PBQeEPglshvi5DI2tD/NvNXyPDfIMM0kj/4cKdrJt6
KP2JqoEUfKAuxZjCajih5QHiDBPCQCpQ6PK1YocCsue9h2VjCng6qGywxTwZAE86
QQznarqSdVHjwX7TFylfTw/wAm06+aQl+rdtkCSyy3ClBnyfxTU2hDrLBQKBgQC7
26i1t3x6TGIlsHmjzyyKArGhl7Zo6QIqymSdjmosAz5WpmHy7QG0+7DvQQYnhUGD
n3VsVXIHCIW8B3ftxIvWv8GjjQ+177rXjAIn/lE29t4qfjL3HkzR/D1n9OrH4y1T
py9/wOpbyaqJ7Dzeesh3Ad5wKJjOhWUXA/suAzWxMwKBgACgGCf0Cimb1bMtEqyI
+l2TZefyvJn98HOpWS9+6wVlRzJeHG7N17Fy3E9z0uEof8DwKNyxLVbVybU5RX+G
74Xqby2wTQlzqsyhgsQ7FJvrJ7lqYD3kdsgRP3Kr1gRSBI9K9z2ME7L7m45LZkfB
pXSwzP6XS4Q7uybdilujk+o4
-----END PRIVATE KEY-----
''';

  static Uint8List getDerFromPem(String pem) {
    final lines = pem.split('\n').where((l) => !l.startsWith('-----') && l.trim().isNotEmpty).join('');
    return Uint8List.fromList(base64.decode(lines));
  }

  static final String defaultCertFingerprint = calculateCertFingerprint(getDerFromPem(_defaultCertPem));

  /// Returns configured SecurityContext for TLS server binding
  static SecurityContext createServerContext({
    String? certPem,
    String? keyPem,
  }) {
    final context = SecurityContext();
    final cert = certPem ?? _defaultCertPem;
    final key = keyPem ?? _defaultKeyPem;

    context.useCertificateChainBytes(utf8.encode(cert));
    context.usePrivateKeyBytes(utf8.encode(key));
    return context;
  }

  /// Calculates the SHA-256 fingerprint of an X.509 certificate in uppercase hex format
  static String calculateCertFingerprint(List<int> derBytes) {
    return sha256.convert(derBytes).toString().toUpperCase();
  }
}
