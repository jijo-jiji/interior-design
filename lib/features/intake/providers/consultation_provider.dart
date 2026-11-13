import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The client the salesperson is designing for right now. Set when they start
/// a new client, before measuring the room, so every auto-saved draft has a
/// name and a stable quote number.
class Consultation {
  const Consultation({
    required this.quoteId,
    this.clientName = '',
    this.clientPhone = '',
  });

  final String quoteId;
  final String clientName;
  final String clientPhone;
}

final consultationProvider = StateProvider<Consultation?>((ref) => null);

/// New quote number, e.g. "QT-19A2F4C1B7E".
String newQuoteId() =>
    'QT-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
