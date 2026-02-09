/// A notification saved locally so admin can view history and open the related order.
class StoredNotification {
  final String id;
  final String title;
  final String body;
  final int? orderId;
  final String date; // ISO 8601
  final bool read;

  const StoredNotification({
    required this.id,
    required this.title,
    required this.body,
    this.orderId,
    required this.date,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'orderId': orderId,
        'date': date,
        'read': read,
      };

  factory StoredNotification.fromJson(Map<String, dynamic> json) {
    final orderId = json['orderId'];
    return StoredNotification(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      orderId: orderId is int? ? orderId : int.tryParse(orderId?.toString() ?? ''),
      date: json['date'] as String? ?? '',
      read: json['read'] as bool? ?? false,
    );
  }

  StoredNotification copyWith({bool? read}) => StoredNotification(
        id: id,
        title: title,
        body: body,
        orderId: orderId,
        date: date,
        read: read ?? this.read,
      );
}
