class SmsEntry {
  final int? id;
  final String address;
  final String body;
  final int timestamp;
  final int receivedAt;
  final bool forwarded;

  const SmsEntry({
    this.id,
    required this.address,
    required this.body,
    required this.timestamp,
    required this.receivedAt,
    this.forwarded = false,
  });

  factory SmsEntry.fromMap(Map<String, Object?> map) {
    return SmsEntry(
      id: map['id'] as int?,
      address: map['address'] as String? ?? '',
      body: map['body'] as String? ?? '',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      receivedAt: (map['received_at'] as num?)?.toInt() ?? 0,
      forwarded: ((map['forwarded'] as num?)?.toInt() ?? 0) != 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'address': address,
      'body': body,
      'timestamp': timestamp,
      'received_at': receivedAt,
      'forwarded': forwarded ? 1 : 0,
    };
  }
}
