/// Dashboard stats returned by GET /api/admin/dashboard
class DashboardModel {
  final double revenueToday;
  final double revenueWeek;
  final double revenueMonth;
  final double paidRevenueToday;
  final double paidRevenueMonth;
  final double pendingRevenue;
  final List<String> ordersLabels;
  final List<int> ordersData;
  final List<double> revenueData;
  final List<String> usersLabels;
  final List<int> usersData;
  final List<String> categoryLabels;
  final List<int> categoryData;
  final List<String> paymentMethodLabels;
  final List<int> paymentMethodData;
  final Map<String, int> paymentStatusData;
  final Map<String, int> orderStatusCounts;
  final int totalTransactions;
  final int successfulTransactions;
  final int pendingTransactions;
  final int failedTransactions;
  final int ordersLast7;
  final int usersLast7;
  final int totalProducts;

  const DashboardModel({
    required this.revenueToday,
    required this.revenueWeek,
    required this.revenueMonth,
    required this.paidRevenueToday,
    required this.paidRevenueMonth,
    required this.pendingRevenue,
    required this.ordersLabels,
    required this.ordersData,
    required this.revenueData,
    required this.usersLabels,
    required this.usersData,
    required this.categoryLabels,
    required this.categoryData,
    required this.paymentMethodLabels,
    required this.paymentMethodData,
    required this.paymentStatusData,
    required this.orderStatusCounts,
    required this.totalTransactions,
    required this.successfulTransactions,
    required this.pendingTransactions,
    required this.failedTransactions,
    required this.ordersLast7,
    required this.usersLast7,
    required this.totalProducts,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    final d = json['data'] as Map<String, dynamic>? ?? json;
    final listStr = (List<dynamic> list) => list.map((e) => e?.toString() ?? '').toList();
    final listInt = (List<dynamic> list) => list.map((e) => _toInt(e)).toList();
    final listDouble = (List<dynamic> list) => list.map((e) => _toDouble(e)).toList();
    final mapStrInt = (Map<String, dynamic>? m) {
      final out = <String, int>{};
      if (m == null) return out;
      for (final e in m.entries) {
        out[e.key] = _toInt(e.value);
      }
      return out;
    };

    return DashboardModel(
      revenueToday: _toDouble(d['revenueToday']),
      revenueWeek: _toDouble(d['revenueWeek']),
      revenueMonth: _toDouble(d['revenueMonth']),
      paidRevenueToday: _toDouble(d['paidRevenueToday']),
      paidRevenueMonth: _toDouble(d['paidRevenueMonth']),
      pendingRevenue: _toDouble(d['pendingRevenue']),
      ordersLabels: listStr((d['ordersLabels'] as List<dynamic>?) ?? []),
      ordersData: listInt((d['ordersData'] as List<dynamic>?) ?? []),
      revenueData: listDouble((d['revenueData'] as List<dynamic>?) ?? []),
      usersLabels: listStr((d['usersLabels'] as List<dynamic>?) ?? []),
      usersData: listInt((d['usersData'] as List<dynamic>?) ?? []),
      categoryLabels: listStr((d['categoryLabels'] as List<dynamic>?) ?? []),
      categoryData: listInt((d['categoryData'] as List<dynamic>?) ?? []),
      paymentMethodLabels: listStr((d['paymentMethodLabels'] as List<dynamic>?) ?? []),
      paymentMethodData: listInt((d['paymentMethodData'] as List<dynamic>?) ?? []),
      paymentStatusData: mapStrInt(d['paymentStatusData'] as Map<String, dynamic>?),
      orderStatusCounts: mapStrInt(d['orderStatusCounts'] as Map<String, dynamic>?),
      totalTransactions: _toInt(d['totalTransactions']),
      successfulTransactions: _toInt(d['successfulTransactions']),
      pendingTransactions: _toInt(d['pendingTransactions']),
      failedTransactions: _toInt(d['failedTransactions']),
      ordersLast7: _toInt(d['ordersLast7']),
      usersLast7: _toInt(d['usersLast7']),
      totalProducts: _toInt(d['totalProducts']),
    );
  }
}
