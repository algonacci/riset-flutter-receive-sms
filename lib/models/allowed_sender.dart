class AllowedSender {
  final int? id;
  final String number;

  const AllowedSender({this.id, required this.number});

  factory AllowedSender.fromMap(Map<String, Object?> map) {
    return AllowedSender(
      id: map['id'] as int?,
      number: map['number'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'number': number,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
