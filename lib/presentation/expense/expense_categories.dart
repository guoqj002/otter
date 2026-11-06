import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/expense.dart';

/// 记账分类（支出 / 收入共用结构）
class ExpenseCategory {
  const ExpenseCategory(this.code, this.label, this.icon, this.color);

  final String code;
  final String label;
  final IconData icon;
  final Color color;
}

/// 支出分类
const kExpenseCategories = <ExpenseCategory>[
  ExpenseCategory('food', '餐饮', Icons.restaurant_rounded, Color(0xFFEF8A3C)),
  ExpenseCategory('traffic', '交通', Icons.directions_bus_rounded, Color(0xFF0EA5E9)),
  ExpenseCategory('shop', '购物', Icons.shopping_bag_rounded, Color(0xFF8B5CF6)),
  ExpenseCategory('fun', '娱乐', Icons.sports_esports_rounded, Color(0xFFEC4899)),
  ExpenseCategory('health', '健康', Icons.favorite_rounded, Color(0xFF22C55E)),
  ExpenseCategory('home', '居住', Icons.home_rounded, Color(0xFF14B8A6)),
  ExpenseCategory('other', '其他', Icons.more_horiz_rounded, Color(0xFF94A3B8)),
];

/// 收入分类
const kIncomeCategories = <ExpenseCategory>[
  ExpenseCategory('salary', '工资', Icons.payments_rounded, Color(0xFF16A34A)),
  ExpenseCategory('bonus', '奖金', Icons.emoji_events_rounded, Color(0xFFF59E0B)),
  ExpenseCategory('invest', '理财', Icons.trending_up_rounded, Color(0xFF0EA5E9)),
  ExpenseCategory('parttime', '兼职', Icons.work_history_rounded, Color(0xFF8B5CF6)),
  ExpenseCategory('redpacket', '红包', Icons.redeem_rounded, Color(0xFFEC4899)),
  ExpenseCategory('otherin', '其他', Icons.more_horiz_rounded, Color(0xFF94A3B8)),
];

ExpenseCategory categoryOf(String code) => kExpenseCategories.firstWhere(
      (c) => c.code == code,
      orElse: () => kExpenseCategories.last,
    );

ExpenseCategory incomeCategoryOf(String code) => kIncomeCategories.firstWhere(
      (c) => c.code == code,
      orElse: () => kIncomeCategories.last,
    );

/// 按流水类型取分类（未知 code 归入"其他"）
ExpenseCategory categoryOfType(String type, String code) =>
    type == ExpenseModel.typeIncome ? incomeCategoryOf(code) : categoryOf(code);

/// 分类映射：code -> 分类对象
Map<String, ExpenseCategory> get kCategoryMap => {
      for (final c in [...kExpenseCategories, ...kIncomeCategories]) c.code: c,
    };

/// 支出主色（橙）
Color get expenseColor => AppColors.seed;

/// 收入主色（绿）
Color get incomeColor => AppColors.success;

/// 金额展示：分 → ¥x.xx
String fmtCents(int cents) {
  final v = cents / 100.0;
  return v == v.roundToDouble()
      ? '¥${v.toStringAsFixed(0)}'
      : '¥${v.toStringAsFixed(2)}';
}
