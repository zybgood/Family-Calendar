class Task {
  final String title;
  final String category;
  final DateTime date;
  final DateTime startTime;
  final DateTime endTime;
  final String notes;
  final List<String> participants;
  final bool reminderEnabled;

  Task({
    required this.title,
    required this.category,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.notes,
    required this.participants,
    required this.reminderEnabled,
  });

  Task copyWith({
    String? title,
    String? category,
    DateTime? date,
    DateTime? startTime,
    DateTime? endTime,
    String? notes,
    List<String>? participants,
    bool? reminderEnabled,
  }) {
    return Task(
      title: title ?? this.title,
      category: category ?? this.category,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      notes: notes ?? this.notes,
      participants: participants ?? this.participants,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    );
  }
}
