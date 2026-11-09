# 水獭管家 · FitStreak

离线优先的**个人管家 App**：习惯打卡 + 记账 + 理财盈亏 + AI 助手小獭，一个 App 管住「坚持、花钱、投资」三件事。
Flutter 单代码库，无需注册，数据只存本机（仅 AI 对话联网）。

> 当前版本 **2.5.2+19** · 应用名「水獭管家」· 包名 `com.fitstreak.fitstreak` · Android 8.0+（minSdk 26）
> 设计文档见 [`docs/设计方案.md`](docs/设计方案.md)

## 功能

底部 6 个 Tab：**今日 · 记账 · 理财 · 小獭 · 统计 · 我的**

### 今日（习惯打卡）

- **一秒钟打卡**：打勾型点一下即完成；计数 / 时长型输入数值或点快捷按钮
- **三种打卡类型**：打勾 / 计数（如 30 个俯卧撑）/ 时长（如 20 分钟）
- **三种频率**：每天 / 每周 N 次 / 指定星期几
- **连续天数**：日频按天、周频按周计算，规则见 `StreakCalculator`
- **热力图 + 月历**：单习惯详情页含月度日历与 26 周热力图
- **本地提醒**：每习惯可设每日提醒时间（本地通知，重启后仍生效）
- **里程碑庆祝**：连续 3 / 7 / 30 / 100 天，累计 10 / 100 次
- **补卡**：设置里开启后可补打最近 7 天；**归档**：暂不用的习惯可归档，随时恢复
- **撤销**：点击已打卡的卡片弹出菜单，可撤销今日打卡或进入详情

### 记账

- **收入 + 支出**双类型，金额以「分」存储，无浮点误差
- **分类**：支出 7 类（餐饮/交通/购物/娱乐/健康/居住/其他）、收入 6 类（工资/奖金/理财/兼职/红包/其他）
- **日 / 月 / 年** 三种周期切换，左右翻页 + 回到今天
- **报表页**：收支趋势柱状图（月模式按天、年模式按月）+ 分类排行（带占比进度条）；日模式只显示分类排行

### 理财

- **四种类型**：股票 / 基金 / ETF / 期货，各有专属图标与配色
- **盈亏记账**：一笔一笔记录当日盈亏（正=盈利红，负=亏损绿，遵循 A 股习惯）
- **日 / 月 / 年** 统计 + **三视图**：柱状图 / 累计折线图 / 月历格
- 侧滑删除单笔记录

### 小獭（AI 助手）

- **数字人家庭助手**：理财管家 + 健康习惯管理 + 饮食建议，一只可爱的卡通水獭
- **看得到你的数据**：自动注入本月收支、支出分类 Top5、理财盈亏和当前习惯列表，回答有据可依
- **能帮你做事**：对话中直接「创建习惯 / 记一笔账 / 记一条理财盈亏」——AI 产出指令卡片，**点「执行」才写库**，可忽略
- **多服务商**：DeepSeek / 通义千问 / 智谱 / Kimi / OpenAI / 自定义，设置里填 API Key 即可；支持测试连接
- 对话历史仅存本机（最多 200 条），不经过任何第三方服务器（除所选模型服务商）

### 统计

- **KPI 卡**：累计打卡、最长连续、本月完成率、在坚持的习惯数
- **打卡趋势**：近 7 / 14 / 30 天柱状图
- **财务概览**：收支环形饼图（中心显示结余）+ 理财盈亏双向柱状图，两张图共用 **日 / 月 / 年** 周期
- **完成率排行**：按习惯列出完成率与应打卡天数

### 我的（设置）

- **外观**：跟随系统 / 浅色 / 深色
- **安全**：6 位密码锁、指纹解锁、离开 30 秒自动锁定、修改密码
- **数据**：导出 JSON（分享面板）、导入 JSON（覆盖式恢复）、查看已归档习惯
- **提醒**：通知权限状态、一键取消全部提醒

## 安全与隐私

| 项 | 实现 |
|---|---|
| 密码存储 | 随机盐 + 12000 轮 SHA-256 摘要，只存摘要不存明文；常量时间比较 |
| 指纹 | 走系统 `local_auth`，App 拿不到任何指纹数据；开启前先验证一次 |
| 锁屏形态 | 覆盖层（`LockGate` 挂在 `MaterialApp.builder`），解锁后原页面状态不丢 |
| 自动锁定 | 切后台超过 30 秒，回前台重新验证 |
| 联网 | 仅 AI 对话需要网络（`INTERNET` 权限，直连所选模型服务商）；其余功能完全离线，无统计 SDK |
| 数据 | 全部落在本机 SQLite + SharedPreferences，卸载即清空 |

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.47 / Dart 3.13 |
| 状态管理 | Riverpod 2（`flutter_riverpod`） |
| 数据库 | Drift 2（SQLite），schemaVersion **4** |
| 路由 | go_router 14（`ShellRoute` + 6 Tab） |
| 通知 | flutter_local_notifications + timezone |
| 生物识别 | local_auth 3 + crypto（SHA-256） |
| AI | http（OpenAI 兼容 /chat/completions） |
| 文件 | share_plus（导出分享）、file_picker（导入） |
| 其他 | shared_preferences、intl、uuid、path_provider |
| 图表 | **全部自绘 CustomPainter**（不引入 fl_chart，包体积可控） |

## 目录结构

```
lib/
├── main.dart / app.dart            # 入口、LockGate 包裹、主题、本地化
├── core/                           # theme / router / utils(date_utils) / notification
├── domain/entities/                # Habit / CheckIn / ExpenseModel / InvestModel
├── model/                          # 数据层：db(Drift) / dao / repositories / row_mappers
├── application/
│   ├── providers/                  # data / settings / expense / invest / lock / ai
│   └── services/                   # streak_calculator / backup_service / lock_service / ai_service / otter_actions
└── presentation/
    ├── shell/main_shell.dart       # 6 Tab 底部导航
    ├── home/                       # 今日页 + 打卡弹层（含里程碑庆祝）
    ├── habit/                      # 新建编辑 / 详情（日历+热力图）
    ├── expense/                    # 记账页 / 报表页 / 分类定义
    ├── invest/                     # 理财页（柱状/折线/日历 三视图）
    ├── ai/                         # 小獭聊天页（指令确认卡片）
    ├── stats/                      # 统计页 / 财务概览图表
    ├── lock/                       # lock_gate / lock_screen / pin_pad / pin_setup
    ├── settings/                   # 我的页（外观/安全/数据/关于）
    ├── onboarding/                 # 欢迎页 + 引导创建
    └── widgets/                    # 通用组件、习惯图标、热力图
assets/habit_icons/                 # 16 张水獭贴纸素材（14 个可选习惯图标 + 头像/理财插画）
docs/设计方案.md                     # 产品与架构设计文档
```

## 数据模型

5 张表（`lib/model/db/app_database.dart`）：

| 表 | 说明 | 关键约束 |
|---|---|---|
| `habits` | 习惯（名称/图标/颜色/类型/目标/频率/提醒/排序/归档） | 主键 `id`（UUID） |
| `check_ins` | 打卡记录 | `UNIQUE(habit_id, local_date)` 防重复，级联删除 |
| `milestones` | 已触发的里程碑（庆祝去重） | 主键 `(habit_id, kind)` |
| `expenses` | 记账流水（`type` = expense/income，金额存分） | 主键 `id` |
| `invest_records` | 理财盈亏（`kind` = stock/fund/etf/futures，金额有符号） | 主键 `id` |

迁移策略：v1 → v2 建 `expenses`；v2 → v3 加 `type` 字段（存量默认支出）；v3 → v4 建 `invest_records`。

## 运行

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 app_database.g.dart
flutter run
```

## 测试

```bash
flutter analyze     # 期望 0 error 0 warning
flutter test        # 62 个用例
```

| 文件 | 用例数 | 覆盖 |
|---|---|---|
| `test/streak_calculator_test.dart` | 17 | 跨月、跨周、非应打卡日、断点、周目标、完成率折算 |
| `test/dao_test.dart` | 8 | 唯一约束、级联删除、统计 SQL |
| `test/lock_service_test.dart` | 6 | 设置/校验/换盐/清空/开关持久化 |
| `test/backup_service_test.dart` | 4 | 导出 payload、导入覆盖、旧版本兼容 |
| `test/invest_test.dart` | 3 | 盈亏聚合、日/月序列 |
| `test/ai_test.dart` | 9 | 服务商预设、baseUrl 归一化、配置持久化 |
| `test/otter_actions_test.dart` | 15 | 指令解析、字段校验兜底、多指令块、正文剔除 |

## 打包

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk（约 66MB，含全 ABI）
```

## 关键设计约定

1. **日期双存**：`check_ins` 同时存 `local_date`（YYYY-MM-DD，按打卡时区）与 `done_at`（UTC ms），避免 UTC 跨日导致日历/连续天数错位。
2. **防重复打卡**：`UNIQUE(habit_id, local_date)` 由数据库兜底，不靠应用层判断。
3. **金额只存整数分**：记账与理财都用 `amountCents`（int），展示时格式化为 `¥x.xx`，杜绝 0.1+0.2 类误差。
4. **盈亏配色**：盈利红 `#E5484D`、亏损绿 `#23A55A`（A 股习惯，与欧美相反）。
5. **统计下推 SQL**：`GROUP BY` 聚合在数据库完成，不把全表捞到 Dart 层。
6. **连续天数**：今天未打卡不算断（沿用昨天的值）；`days` 频率下非应打卡日既不累计也不中断。
7. **跨天刷新**：`todayProvider` 由定时器 + `AppLifecycleState.resumed` 双保险驱动。
8. **习惯图标**：以 Unicode 码点作存储键（`iconCode`），14 个可选项通过 `kHabitIconCodes` 注册，旧码点由 `_legacyToArt` 映射到贴纸 PNG，新增图标 = 加一张 assets + 一条映射。
9. **备份格式**：`version: 2`，含 habits / checkIns / milestones / expenses / investRecords / settings，导入走事务覆盖式恢复；旧备份缺字段按默认值兜底。
10. **图表零依赖**：饼图、双向柱状、累计折线、热力图全部 `CustomPainter` 自绘。
11. **AI 指令协议**：小獭的写操作走 ```otter 围栏 JSON（App 解析，不依赖服务商 Function Calling），UI 渲染成确认卡片，用户点「执行」才写库；字段全部服务端无关校验兜底（非法金额/分类/日期自动修正或拒绝）。

## 版本记录

| 版本 | 内容 |
|---|---|
| v1.0.0 | 习惯打卡基础版：打卡、连续天数、热力图、提醒、里程碑 |
| v2.0.0 | 引入记账（收支 + 日/月/年 + 报表） |
| v2.1.0 | 数据导入导出（JSON） |
| v2.2.0 | 欢迎页/设置页文案与图标改版，新增水獭俯卧撑图标 |
| v2.2.1 | 桌面图标重设计为「水獭管家」 |
| v2.3.0 | 新增理财模块（股票/基金，柱状/折线/日历） |
| v2.4.0 | 密码锁 + 指纹解锁 + 自动锁定 |
| v2.4.1 | 理财空状态换「水獭炒股」插画 |
| v2.4.2 | 统计页图标改饼图，新增收支环形图与理财盈亏柱图 |
| v2.4.3 | 统计页财务概览支持日/月/年切换 |
| v2.4.4 | 理财类型新增 ETF、期货 |
| v2.5.0 | 新增 AI 助手「小獭」（数字人理财管家），模型与 Key 在设置里配置 |
| v2.5.1 | AI 支持多服务商预设：DeepSeek / 通义千问 / 智谱 / Kimi / OpenAI / 自定义 |
| v2.5.2 | 小獭角色扩展为家庭助手（理财 + 健康习惯 + 饮食），支持对话创建习惯、记账、记理财盈亏（指令卡片确认后写库） |
