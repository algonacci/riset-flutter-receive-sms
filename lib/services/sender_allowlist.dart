class SenderAllowlist {
  const SenderAllowlist(this.numbers);

  final List<String> numbers;

  static String normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (digits.startsWith('8')) {
      digits = '62$digits';
    }
    return digits;
  }

  bool allows(String address) {
    if (numbers.isEmpty) return true;
    return numbers.contains(normalize(address));
  }
}
