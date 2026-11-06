/// 理财：股票 / 基金 / ETF / 期货每日盈亏记录
class InvestModel {
  const InvestModel({
    required this.id,
    required this.kind,
    required this.amountCents,
    this.note,
    required this.localDate,
    required this.createdAt,
  });

  static const kindStock = 'stock';
  static const kindFund = 'fund';
  static const kindEtf = 'etf';
  static const kindFutures = 'futures';

  /// 全部支持的类型（录入面板按此顺序展示）
  static const kinds = [kindStock, kindFund, kindEtf, kindFutures];

  final String id;
  final String kind; // stock | fund | etf | futures
  final int amountCents; // 有符号：正=盈利，负=亏损
  final String? note;
  final String localDate; // YYYY-MM-DD
  final int createdAt; // epoch ms UTC

  double get amount => amountCents.abs() / 100.0;
  bool get isProfit => amountCents >= 0;

  static String labelOf(String kind) => switch (kind) {
        kindStock => '股票',
        kindFund => '基金',
        kindEtf => 'ETF',
        kindFutures => '期货',
        _ => '其他',
      };

  static String shortLabelOf(String kind) => switch (kind) {
        kindStock => '股',
        kindFund => '基',
        kindEtf => 'E',
        kindFutures => '期',
        _ => '其',
      };
}
