# 混淆规则：Drift / sqlite3 通过反射访问，必须保留
-keep class com.drift.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class net.sqlcipher.** { *; }

# 本地通知
-keep class com.dexterous.** { *; }

# 保留行号，便于崩溃定位
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
