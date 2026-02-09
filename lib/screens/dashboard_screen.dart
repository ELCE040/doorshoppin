import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/dashboard_model.dart';
import '../models/order_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'orders_list_screen.dart';

const Color appGreen = Color(0xFF28b244);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.showAppBar = true, this.onNavigateToOrders});

  static const routeName = '/dashboard';
  final bool showAppBar;
  final VoidCallback? onNavigateToOrders;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  DashboardModel? _stats;
  List<OrderModel> _orders = [];

  @override
  void initState() {
    super.initState();
    debugPrint('[Dashboard] initState, loading data');
    // Defer load so the loading spinner can paint first (reduces "Skipped N frames" on startup).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  /// When dashboard API is missing (e.g. "Route not found"), we still show orders and a fallback message.
  String? _dashboardUnavailable;

  Future<void> _loadData() async {
    debugPrint('[Dashboard] _loadData start');
    setState(() {
      _loading = true;
      _error = null;
      _dashboardUnavailable = null;
    });
    List<OrderModel> orders = [];
    try {
      orders = await ApiService.getAdminOrders();
    } catch (e) {
      debugPrint('[Dashboard] getAdminOrders error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    // Show orders first so the UI updates quickly (smaller setState).
    setState(() {
      _orders = orders;
      _loading = false;
    });
    DashboardModel? stats;
    try {
      stats = await ApiService.getDashboardStats();
    } catch (e) {
      debugPrint('[Dashboard] getDashboardStats error (optional): $e');
      _dashboardUnavailable = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      _stats = stats;
    });
  }

  String _fmt(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  int _countByStatus(String status) =>
      _orders.where((o) => o.status.toLowerCase() == status.toLowerCase()).length;

  double get _revenueTodayFromOrders {
    final today = DateTime.now();
    return _orders.where((o) {
      if (o.createdAt == null) return false;
      final dt = DateTime.tryParse(o.createdAt!);
      if (dt == null) return false;
      return dt.year == today.year && dt.month == today.month && dt.day == today.day;
    }).fold(0.0, (sum, o) => sum + o.totalAmount);
  }

  Widget _buildFallbackOverview() {
    return _AdminCard(
      title: 'Overview',
      icon: Icons.receipt_long,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text('${_orders.length}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: appGreen)),
              Text('Total orders', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          Column(
            children: [
              Text('MK ${_revenueTodayFromOrders.toStringAsFixed(0)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.blue.shade700)),
              Text('Revenue today', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          Column(
            children: [
              Text('${_countByStatus('pending')}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.orange)),
              Text('Pending', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'DoorShoppin Dashboard',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              backgroundColor: appGreen,
              foregroundColor: Colors.white,
              actions: [
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _loadData),
                IconButton(
                  icon: const Icon(Icons.list_alt),
                  tooltip: 'View Orders',
                  onPressed: () {
                    if (widget.onNavigateToOrders != null) {
                      widget.onNavigateToOrders!();
                    } else {
                      Navigator.of(context).pushNamed(OrdersListScreen.routeName);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await AuthService.logout();
                    if (!mounted) return;
                    Navigator.of(context).pushReplacementNamed(LoginScreen.routeName);
                  },
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: appGreen))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: appGreen,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_dashboardUnavailable != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 20, color: Colors.orange.shade800),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Charts and full stats need a backend update. Deploy the latest doorshoppin_backend to enable them.',
                                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_stats != null) ...[
                        _buildTopStats(_stats!),
                        const SizedBox(height: 16),
                        _buildOrderAndPaymentStatus(_stats!),
                        const SizedBox(height: 16),
                        _buildChartsRow(_stats!),
                        const SizedBox(height: 16),
                      ] else if (_orders.isNotEmpty) ...[
                        _buildFallbackOverview(),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Orders',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          TextButton(
                            onPressed: () {
                              if (widget.onNavigateToOrders != null) {
                                widget.onNavigateToOrders!();
                              } else {
                                Navigator.of(context).pushNamed(OrdersListScreen.routeName);
                              }
                            },
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._orders.take(5).map((o) => _RecentOrderTile(order: o, onNavigateToOrders: widget.onNavigateToOrders)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTopStats(DashboardModel s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _RevenueStatCard(
              value: s.revenueToday,
              label: 'Revenue Today',
              subtitle: 'Paid: MK ${_fmt(s.paidRevenueToday)}',
              icon: Icons.attach_money,
              color: Colors.blue,
            ),
            _RevenueStatCard(
              value: s.revenueWeek,
              label: 'Revenue This Week',
              icon: Icons.calendar_today,
              color: appGreen,
            ),
            _RevenueStatCard(
              value: s.revenueMonth,
              label: 'Revenue This Month',
              subtitle: 'Paid: MK ${_fmt(s.paidRevenueMonth)}',
              icon: Icons.calendar_month,
              color: Colors.orange,
            ),
            _RevenueStatCard(
              value: s.pendingRevenue,
              label: 'Pending Revenue',
              icon: Icons.schedule,
              color: Colors.teal,
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrderAndPaymentStatus(DashboardModel s) {
    final orderCounts = s.orderStatusCounts;
    final paymentCounts = s.paymentStatusData;
    final orderCard = _AdminCard(
      title: 'Order Status',
      icon: Icons.shopping_bag,
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniStat(label: 'Pending', value: orderCounts['pending'] ?? 0, color: Colors.orange),
          _MiniStat(label: 'Processing', value: orderCounts['processing'] ?? 0, color: Colors.blue),
          _MiniStat(label: 'Out for Delivery', value: orderCounts['out_for_delivery'] ?? 0, color: Colors.indigo),
          _MiniStat(label: 'Delivered', value: orderCounts['delivered'] ?? 0, color: appGreen),
          _MiniStat(label: 'Cancelled', value: orderCounts['cancelled'] ?? 0, color: Colors.red),
        ],
      ),
    );
    final paymentCard = _AdminCard(
      title: 'Payment Status',
      icon: Icons.credit_card,
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniStat(label: 'Paid', value: paymentCounts['paid'] ?? 0, color: appGreen),
          _MiniStat(label: 'Pending', value: paymentCounts['pending'] ?? 0, color: Colors.orange),
          _MiniStat(label: 'Failed', value: paymentCounts['failed'] ?? 0, color: Colors.red),
          _MiniStat(label: 'Refunded', value: paymentCounts['refunded'] ?? 0, color: Colors.blue),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              orderCard,
              const SizedBox(height: 12),
              paymentCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: orderCard),
            const SizedBox(width: 12),
            Expanded(child: paymentCard),
          ],
        );
      },
    );
  }

  Widget _buildChartsRow(DashboardModel s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _AdminCard(
                      title: 'Orders Last 7 Days',
                      icon: Icons.shopping_cart,
                      child: SizedBox(
                        height: 180,
                        child: _OrdersLineChart(labels: s.ordersLabels, data: s.ordersData),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AdminCard(
                      title: 'Revenue Trend',
                      icon: Icons.show_chart,
                      child: SizedBox(
                        height: 180,
                        child: _RevenueBarChart(labels: s.ordersLabels, data: s.revenueData),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _AdminCard(
                      title: 'Payment Methods',
                      icon: Icons.account_balance_wallet,
                      child: SizedBox(
                        height: 200,
                        child: _PaymentMethodChart(
                          labels: s.paymentMethodLabels,
                          data: s.paymentMethodData,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AdminCard(
                      title: 'Products per Category',
                      icon: Icons.category,
                      child: SizedBox(
                        height: 200,
                        child: _ProductsPieChart(
                          labels: s.categoryLabels,
                          data: s.categoryData,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AdminCard(
                      title: 'Transaction Stats',
                      icon: Icons.pie_chart,
                      child: _TransactionStats(
                        total: s.totalTransactions,
                        successful: s.successfulTransactions,
                        pending: s.pendingTransactions,
                        failed: s.failedTransactions,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AdminCard(
                      title: 'Quick Stats',
                      icon: Icons.insights,
                      child: _QuickStats(
                        orders7: s.ordersLast7,
                        users7: s.usersLast7,
                        totalProducts: s.totalProducts,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _AdminCard(
              title: 'Orders Last 7 Days',
              icon: Icons.shopping_cart,
              child: SizedBox(
                height: 180,
                child: _OrdersLineChart(labels: s.ordersLabels, data: s.ordersData),
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              title: 'Revenue Trend',
              icon: Icons.show_chart,
              child: SizedBox(
                height: 180,
                child: _RevenueBarChart(labels: s.ordersLabels, data: s.revenueData),
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              title: 'Payment Methods',
              icon: Icons.account_balance_wallet,
              child: SizedBox(
                height: 200,
                child: _PaymentMethodChart(
                  labels: s.paymentMethodLabels,
                  data: s.paymentMethodData,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              title: 'Products per Category',
              icon: Icons.category,
              child: SizedBox(
                height: 200,
                child: _ProductsPieChart(
                  labels: s.categoryLabels,
                  data: s.categoryData,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              title: 'Transaction Stats',
              icon: Icons.pie_chart,
              child: _TransactionStats(
                total: s.totalTransactions,
                successful: s.successfulTransactions,
                pending: s.pendingTransactions,
                failed: s.failedTransactions,
              ),
            ),
            const SizedBox(height: 12),
            _AdminCard(
              title: 'Quick Stats',
              icon: Icons.insights,
              child: _QuickStats(
                orders7: s.ordersLast7,
                users7: s.usersLast7,
                totalProducts: s.totalProducts,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RevenueStatCard extends StatelessWidget {
  final double value;
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _RevenueStatCard({
    required this.value,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            'MK ${value.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _AdminCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: appGreen),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _OrdersLineChart extends StatelessWidget {
  final List<String> labels;
  final List<int> data;

  const _OrdersLineChart({required this.labels, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No data'));
    }
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.toDouble())).toList();
    final maxY = (data.isEmpty ? 1 : data.reduce((a, b) => a > b ? a : b)).toDouble();
    if (maxY == 0) return const Center(child: Text('No orders'));

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.2))),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i >= 0 && i < labels.length) return Text(labels[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
            return const SizedBox();
          })),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.1 + 1,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF3498db),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF3498db).withOpacity(0.1)),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 200),
    );
  }
}

class _RevenueBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> data;

  const _RevenueBarChart({required this.labels, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No data'));
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = data.isEmpty ? 1.0 : data.reduce((a, b) => a > b ? a : b);
    final maxYVal = maxY * 1.15 + 100;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxYVal,
        minY: 0,
        barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final v = rod.toY;
            return BarTooltipItem('MK ${v.toStringAsFixed(0)}', TextStyle(color: Colors.white, fontSize: 12));
          },
        )),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i >= 0 && i < labels.length) return Text(labels[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
            return const SizedBox();
          })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toInt().toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.2))),
        borderData: FlBorderData(show: false),
        barGroups: data.asMap().entries.map((e) => BarChartGroupData(
          x: e.key,
          barRods: [BarChartRodData(toY: e.value, color: appGreen, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
          showingTooltipIndicators: [0],
        )).toList(),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }
}

final List<Color> _chartColors = [
  const Color(0xFF3498db),
  const Color(0xFF2ecc71),
  const Color(0xFFf1c40f),
  const Color(0xFFe74c3c),
  const Color(0xFF9b59b6),
  const Color(0xFF1abc9c),
];

class _PaymentMethodChart extends StatelessWidget {
  final List<String> labels;
  final List<int> data;

  const _PaymentMethodChart({required this.labels, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No data'));
    final total = data.reduce((a, b) => a + b);
    if (total == 0) return const Center(child: Text('No payments'));

    final sections = data.asMap().entries.map((e) => PieChartSectionData(
      value: e.value.toDouble(),
      title: '${e.value}',
      color: _chartColors[e.key % _chartColors.length],
      radius: 48,
      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
    )).toList();

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 32,
              sectionsSpace: 2,
            ),
            duration: const Duration(milliseconds: 200),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: labels.asMap().entries.map((e) {
              if (e.key >= data.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _chartColors[e.key % _chartColors.length], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        e.value,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ProductsPieChart extends StatelessWidget {
  final List<String> labels;
  final List<int> data;

  const _ProductsPieChart({required this.labels, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No products'));
    final total = data.reduce((a, b) => a + b);
    if (total == 0) return const Center(child: Text('No products'));

    final sections = data.asMap().entries.map((e) => PieChartSectionData(
      value: e.value.toDouble(),
      title: '${e.value}',
      color: _chartColors[e.key % _chartColors.length],
      radius: 52,
      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
    )).toList();

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
            ),
            duration: const Duration(milliseconds: 200),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: labels.asMap().entries.map((e) {
              if (e.key >= data.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _chartColors[e.key % _chartColors.length], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        e.value,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _TransactionStats extends StatelessWidget {
  final int total;
  final int successful;
  final int pending;
  final int failed;

  const _TransactionStats({required this.total, required this.successful, required this.pending, required this.failed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            Text('$total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.blue.shade700)),
            Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Column(
          children: [
            Text('$successful', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: appGreen)),
            Text('Successful', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Column(
          children: [
            Text('$pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.orange)),
            Text('Pending', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Column(
          children: [
            Text('$failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red)),
            Text('Failed', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}

class _QuickStats extends StatelessWidget {
  final int orders7;
  final int users7;
  final int totalProducts;

  const _QuickStats({required this.orders7, required this.users7, required this.totalProducts});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            Text('$orders7', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.blue.shade700)),
            Text('Orders (7d)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Column(
          children: [
            Text('$users7', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: appGreen)),
            Text('New Users (7d)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Column(
          children: [
            Text('$totalProducts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.teal)),
            Text('Total Products', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onNavigateToOrders;

  const _RecentOrderTile({required this.order, this.onNavigateToOrders});

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'delivering':
      case 'out_for_delivery':
        return Colors.indigo;
      case 'completed':
      case 'delivered':
        return appGreen;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.schedule;
      case 'processing':
        return Icons.autorenew;
      case 'delivering':
      case 'out_for_delivery':
        return Icons.local_shipping;
      case 'completed':
      case 'delivered':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.receipt_long;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(order.status).withOpacity(0.15),
          child: Icon(_statusIcon(order.status), color: _statusColor(order.status)),
        ),
        title: Text(
          order.orderTrackingId ?? '#${order.id}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          order.customerName ?? 'Guest',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'MK ${order.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: appGreen),
            ),
            const SizedBox(height: 4),
            Text(
              order.status,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _statusColor(order.status)),
            ),
          ],
        ),
        onTap: () {
          if (onNavigateToOrders != null) {
            onNavigateToOrders!();
          } else {
            Navigator.of(context).pushNamed(OrdersListScreen.routeName);
          }
        },
      ),
    );
  }
}
