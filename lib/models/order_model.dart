/// Parse JSON value to double; accepts num or String from backend.
double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

class OrderModel {
  final int id;
  final int? userId;
  final String status;
  final String? paymentStatus;
  final String? paymentMethod;
  final double totalAmount;
  final double? subtotal;
  final double? deliveryFee;
  final double? serviceFee;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? placeDescription;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? orderTrackingId;
  final String? createdAt;
  final int? adminId;
  final List<OrderItemModel> items;

  OrderModel({
    required this.id,
    this.userId,
    required this.status,
    this.paymentStatus,
    this.paymentMethod,
    required this.totalAmount,
    this.subtotal,
    this.deliveryFee,
    this.serviceFee,
    this.latitude,
    this.longitude,
    this.address,
    this.placeDescription,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.orderTrackingId,
    this.createdAt,
    this.adminId,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    return OrderModel(
      id: (json['id'] is int) ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: json['userId'] != null ? (json['userId'] is int ? json['userId'] as int : int.tryParse(json['userId'].toString())) : null,
      status: json['status']?.toString() ?? 'pending',
      paymentStatus: json['paymentStatus']?.toString(),
      paymentMethod: json['paymentMethod']?.toString(),
      totalAmount: _toDouble(json['totalAmount']) ?? 0,
      subtotal: _toDouble(json['subtotal']),
      deliveryFee: _toDouble(json['deliveryFee']),
      serviceFee: _toDouble(json['serviceFee']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      address: json['address']?.toString(),
      placeDescription: json['placeDescription']?.toString(),
      customerName: json['customerName']?.toString(),
      customerPhone: json['customerPhone']?.toString(),
      customerEmail: json['customerEmail']?.toString(),
      orderTrackingId: json['orderTrackingId']?.toString(),
      createdAt: json['createdAt']?.toString(),
      adminId: json['adminId'] != null ? (json['adminId'] is int ? json['adminId'] as int : int.tryParse(json['adminId'].toString())) : null,
      items: itemsList != null ? itemsList.map((e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e as Map))).toList() : [],
    );
  }

  bool get hasLocation => latitude != null && longitude != null;
}

class OrderItemModel {
  final int? productId;
  final String? productName;
  final int quantity;
  final double? unitPrice;
  final double? subtotal;

  OrderItemModel({
    this.productId,
    this.productName,
    required this.quantity,
    this.unitPrice,
    this.subtotal,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      productId: json['productId'] != null ? (json['productId'] is int ? json['productId'] as int : int.tryParse(json['productId'].toString())) : null,
      productName: json['productName']?.toString(),
      quantity: json['quantity'] is int ? json['quantity'] as int : int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      unitPrice: _toDouble(json['unitPrice']),
      subtotal: _toDouble(json['subtotal']),
    );
  }
}
