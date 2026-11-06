/// Where a client project is in the sale.
enum ProjectStatus {
  /// Being designed; saved on the phone, never sent.
  draft,

  /// Quote sent to the client.
  quote,

  /// Client paid a deposit.
  deposit;

  String get label => switch (this) {
        ProjectStatus.draft => 'Draft',
        ProjectStatus.quote => 'Quote sent',
        ProjectStatus.deposit => 'Deposit paid',
      };

  /// Reads a saved project record. Records saved before statuses existed
  /// were always sent quotes.
  static ProjectStatus of(Map<String, dynamic> project) {
    if (((project['deposit_paid'] as num?) ?? 0) > 0) {
      return ProjectStatus.deposit;
    }
    return switch (project['status']) {
      'draft' => ProjectStatus.draft,
      'deposit' => ProjectStatus.deposit,
      _ => ProjectStatus.quote,
    };
  }
}
