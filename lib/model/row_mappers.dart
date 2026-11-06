import 'package:drift/drift.dart';

import '../domain/entities/habit.dart' as domain;
import 'db/app_database.dart';

extension HabitRowMapper on Habit {
  domain.HabitModel toEntity() => domain.HabitModel(
        id: id,
        name: name,
        iconCode: iconCode,
        colorHex: colorHex,
        type: domain.HabitType.fromDb(type),
        targetValue: targetValue,
        unit: unit,
        frequency: domain.HabitFrequency.fromDb(frequency),
        weeklyTarget: weeklyTarget,
        weekdaysMask: weekdaysMask,
        reminderTime: reminderTime,
        sortOrder: sortOrder,
        archivedAt: archivedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

extension CheckInRowMapper on CheckIn {
  domain.CheckInModel toEntity() => domain.CheckInModel(
        id: id,
        habitId: habitId,
        localDate: localDate,
        doneAt: doneAt,
        value: value,
        note: note,
        deletedAt: deletedAt,
      );
}

extension HabitToCompanion on domain.HabitModel {
  HabitsCompanion toCompanion() => HabitsCompanion(
        id: Value(id),
        name: Value(name),
        iconCode: Value(iconCode),
        colorHex: Value(colorHex),
        type: Value(type.name),
        targetValue: Value(targetValue),
        unit: Value(unit),
        frequency: Value(frequency.name),
        weeklyTarget: Value(weeklyTarget),
        weekdaysMask: Value(weekdaysMask),
        reminderTime: Value(reminderTime),
        sortOrder: Value(sortOrder),
        archivedAt: Value(archivedAt),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
      );
}
