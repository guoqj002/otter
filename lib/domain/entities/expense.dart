/// 记账：流水领域模型（支出 / 收入）
class ExpenseModel {
  const ExpenseModel({
    required this.id,
    required this.category,
    required this.amountCents,
    this.type = 'expense',
    this.note,
    required this.localDate,
    required this.createdAt,
  });

  static const typeExpense = 'expense';
  static const typeIncome = 'income';

  final String id;
  final String category; // 见 presentation/expense/expense_categories.dart
  final int amountCents; // 分（正数，方向由 type 决定）
  final String type; // expense | income
  final String? note;
  final String localDate; // YYYY-MM-DD
  final int createdAt; // epoch ms UTC

  double get amount => amountCents / 100.0;
  bool get isIncome => type == typeIncome;
}
