# 鬼個人経理 (oni-keiri) v1 — 基盤 + コア機能 設計

- 作成: 2026-08-06 Architect (モック v0.6 確定を反映した確定版)
- 対象リポジトリ: `Muraki/projects/oni-keiri/` (新規。既存コードなし)
- 実装エンジン: **Codex (`codex exec`)** — 本 doc は推測余地を残さないことを最優先に、型・export 名・定数・数式を全て明示する
- 参照正典:
  - **UI: `.designs/20260806-mock-v0.6.html` (mock v0.6、Touri 確定。scratchpad から複製済み)** — 視覚の正典。ただし**モック内の金額・%・件数の例示値は装飾であり導出根拠にしない** (数式は本 doc §4 が規範)。§9 はモックから抽出したトークン/骨格
  - 認証実装: `Muraki/projects/atender/apps/api/src/auth.ts` / `src/middleware/session.ts` / `apps/ios/Atender/Core/Auth/{AppleSignIn,AuthStore,KeychainStore}.swift`
  - materialize: `Muraki/knowledge/pattern/recurring-rule-materialize-unpaid-records.md` + `gotcha/lazy-materialize-rolling-vs-edit-conflict.md`
  - UI 観点: `Muraki/knowledge/pattern/ui-ux-design-perspectives.md` §7

---

## 1. 目的

大目的は**「日常の出費を意識できて、金銭的な余裕を生み出す」**こと (キャッシュフローの管理そのものは手段)。機能の優先度はこの軸で決める — 出費の意識化 (最短入力・内訳・支出の質) と余裕の可視化 (残額・貯金見込み・支払いの見通し・税金の取り置き) を優先し、管理のための管理 (詳細な口座残高追跡・レポート) は作らない。1-2 タップで基本機能、3 タブ。

## 2. スコープ / Phase 分割

実行単位は 2 Phase に畳む (Touri 方針: Architect の細分割をそのまま実行単位にしない)。**DB migration は Phase 1 で全テーブルを 1 本で作る** (Phase 2 で migration を増やさない)。

| Phase | 内容 |
|---|---|
| **Phase 1 (縦切り)** | monorepo scaffold / 全スキーマ + 初回 migration / SIWA 認証 / **API 全部** (`/api/me` `/api/settings` `/api/home` `/api/entries`(+salary) `/api/cards`(+detail) `/api/recurring-rules` `/api/calendar` `/api/tax/estimate` — materialize・カードスケジュール込み。DB 依存テストを 1 回で回すためサーバは一気通貫) / iOS: サインイン → オンボーディング (働き方 4 択) → **ホームタブ** (hero + クイック 3 + 機能グリッド + 今後の支払い + 残高推移) + **入力モーダル** + **記録タブ** (内訳 + 支出の質 + 日別リスト) + **設定タブ** (働き方/貯金目標/ログアウト) / Coolify デプロイ |
| **Phase 2** | iOS push 画面群: 支払いカレンダー / サブスク・定額一覧 + ルールフォーム / カード一覧・詳細 + カードフォーム / 給与一覧 / 税金目安 / アカウント削除 / TestFlight 配布 |

Phase 1 のホームはカード・ルール 0 件でも成立する (今後の支払い空・カード項 0 円)。Phase 2 は API 追加ゼロ (画面だけ)。

## 3. 技術スタック / リポジトリ構成 (確定決定。逸脱しない)

- API: Hono 4.x + TypeScript 5.x + **Postgres + Drizzle** (`drizzle-orm/node-postgres` + `pg` ^8)。better-auth **^1.6.26** (`drizzleAdapter(db, { provider: "pg" })` + `bearer()` plugin)。zod v4 (better-auth 要求)
- iOS: Swift 6.0 / SwiftUI / deployment target iOS 17.0 / XcodeGen (atender `project.yml` 流用) / bundle id `net.appily.onikeiri` / **Swift Charts 使用** (残高推移 + 支出内訳ドーナツ、§10.4)
- 金額: **JPY 整数円** (Decimal 禁止。DB/JSON/Swift 全て Int)
- ホスティング: Appily レーン (Coolify + managed Postgres)、`onikeiri.appily.run`。TestFlight は atender/CLAUDE.md の CLI 手順流用 (fastlane 不使用)
- repo は **public** (`ait913/oni-keiri`。Coolify Public Repo build pack が private を clone できないため)

```
oni-keiri/
├── CLAUDE.md
├── package.json / pnpm-workspace.yaml        # workspace: apps/api のみ (将来 web 拡張余地)
├── apps/api/
│   ├── src/
│   │   ├── index.ts          # migrate() → serve() の薄い起動 wrapper (テストは import しない)
│   │   ├── app.ts            # ★ export const app (named)。テストの唯一の接続点
│   │   ├── auth.ts           # better-auth 構成 (atender auth.ts の getAuth/Proxy/lazy 構造を踏襲)
│   │   ├── env.ts            # lazy 読み (import 時 parse 禁止 → §11.3)
│   │   ├── db/
│   │   │   ├── index.ts      # export function getDb() / resetDb() (lazy singleton)
│   │   │   ├── auth-schema.ts # `npx @better-auth/cli generate` 生成 (user/session/account/verification, pg)
│   │   │   └── schema.ts     # 業務テーブル (§5)
│   │   ├── middleware/
│   │   │   ├── session.ts    # sessionMiddleware (atender 版の drizzle 移植)
│   │   │   └── materialize.ts # ensureMaterialized (§7 の対象 route 一覧参照)
│   │   ├── lib/
│   │   │   ├── appError.ts   # export class AppError extends Error { status; code; message }
│   │   │   ├── tz.ts         # export const APP_TZ = "Asia/Tokyo"; todayJst(); currentMonthJst(); addMonths()
│   │   │   ├── money.ts      # clampDay / isValidDate / yearMonthOf
│   │   │   ├── cardSchedule.ts # cycleRange / cardPaymentSchedule / cardUtilization (§4.3, 純関数)
│   │   │   ├── materialize.ts  # ensureMaterializedForUser / rematerializeRule (§4.4)
│   │   │   ├── homeSummary.ts  # buildHomeSummary / buildDailySeries / buildBreakdown / buildQuality (§4.2/4.6/4.7)
│   │   │   ├── calendar.ts     # buildCalendarEvents (§4.7)
│   │   │   └── tax.ts          # TAX_BRACKETS / taxEstimate (§4.5, 純関数)
│   │   └── routes/           # home.ts / entries.ts / cards.ts / recurringRules.ts / calendar.ts / tax.ts / settings.ts / me.ts
│   ├── drizzle/              # migration SQL (drizzle-kit generate 出力)
│   ├── drizzle.config.ts / vitest.config.ts / tsconfig.json
│   ├── docker-compose.test.yml   # postgres:16-alpine, port 54329 (テスト専用)
│   ├── Dockerfile
│   └── tests/ { unit/ , api/ , setup/ }
└── apps/ios/
    ├── project.yml
    ├── OniKeiri/
    │   ├── App/            # OniKeiriApp.swift / RootView.swift / AppEnvironment.swift
    │   ├── Core/
    │   │   ├── Auth/       # AppleSignIn.swift / AuthStore.swift / KeychainStore.swift (atender 移植)
    │   │   ├── API/        # APIConfig.swift / APIClient.swift / APIError.swift / DTO.swift
    │   │   └── Design/     # DS.swift (§9.1) / YenText.swift / ServiceTile.swift / BalanceLineChart.swift / CategoryDonutChart.swift ほか (§10.4)
    │   └── Features/       # Home/ Records/ EntryInput/ Calendar/ Subs/ Cards/ Salary/ Tax/ Settings/ Onboarding/
    └── OniKeiriTests/
```

## 4. 用語と数理モデル (Reviewer 必読。実装はこの節の式に従う)

### 4.1 日付・タイムゾーン

- 業務日付は全て **`YYYY-MM-DD` 文字列** (pg `date` 型、Drizzle string mode)。月は `YYYY-MM` 文字列。timestamp を業務日付に使わない
- `src/lib/tz.ts`:
  ```ts
  export const APP_TZ = "Asia/Tokyo";
  export function todayJst(now: Date = new Date()): string;        // "2026-08-06"
  export function currentMonthJst(now: Date = new Date()): string; // "2026-08"
  export function addMonths(yearMonth: string, n: number): string; // "2026-12"+2 → "2027-02"
  ```
  実装は `Intl.DateTimeFormat("en-CA", { timeZone: APP_TZ })` 系。サーバプロセスの TZ に依存しない (本番コンテナは UTC)
- クライアントは日付演算をしない (集計は全てサーバ)。例外は表示専用の 2 つ: ヘッダの「あと N 日」(= 月末日 − today の日数。today はサーバ値) と入力モーダルの既定日付 (= 直近 `GET /api/home` の `today`)

### 4.2 残額まわりの導出値 (Home hero の定義。唯一の定義)

銀行残高・月跨ぎ繰越は**扱わない** (v1 は月内完結。§13-11)。対象月 M、貯金目標 `savingsGoal` (null=未設定):

```
income(M)         = Σ entry(kind=income,       yearMonth=M, deletedAt=null).amount   // 給与ルール生成分・未来日付含む
cashExpense(M)    = Σ entry(kind=expense,      yearMonth=M, deletedAt=null).amount   // 未来日付の定額予定を含む
cardPaymentDue(M) = Σ_cards due_{c,M}                                                // §4.3。支払日が過去でも当月分は含む
cardUsage(M)      = Σ entry(kind=card_expense, yearMonth=M, deletedAt=null).amount   // 表示用参考値
spending(M)       = cashExpense(M) + cardPaymentDue(M)                               // hero foot「支出・予定込み」

remaining(M)      = income(M) − spending(M)           // 月末見込み。「貯金見込み」の表示値
spendable(M)      = remaining(M) − (savingsGoal ?? 0) // ★「今月あと使える額」(hero 主数値)。貯金目標を先取りした後の可処分額
```

card_expense は**利用月でなく支払月に効く** (二重計上禁止)。remaining / spendable は負になり得る (クランプしない、負は red 表示)。
「今月あと使える額 = 目標先取り後」はプロダクト軸 (§1 余裕を生み出す = 目標を守る前提の可処分額) から採った定義 — **§14-6 判断点**。

例 (E-3): M=2026-08、income=300,000 / cashExpense=45,000 / cardPaymentDue=18,000 / savingsGoal=100,000 → remaining=237,000、spendable=137,000、spending=63,000。

### 4.3 カード支払サイクル (純関数 `src/lib/cardSchedule.ts`)

カード c: `closingDay` (締め日 1-31)、`paymentDay` (支払日 1-31)、`revolvingAmount` (リボ月額、null=一括)、`carryoverBalance` (登録時点の未払い残高 ≥0)。

```
clampDay(yearMonth, day) = min(day, その月の日数) の日付           // 31 → 2月は 28/29
closing(m)   = clampDay(m, closingDay)
支払月 M のサイクル = ( closing(M−2), closing(M−1) ]               // fromExclusive, toInclusive
paymentDate(M) = clampDay(M, paymentDay)
```

**支払額の漸化式** (一括・リボ統一。B₀ = carryoverBalance):

```
P_M   = Σ card_expense(c, date ∈ サイクル(M), deletedAt=null).amount
due_M = revolvingAmount == null ? B_{M−1} + P_M : min(revolvingAmount, B_{M−1} + P_M)
B_M   = B_{M−1} + P_M − due_M                                      // 一括なら常に 0
```

- 初回支払月 M₁ = mc + 1ヶ月。mc = `closing(mc) ≥ カード作成日 (JST)` を満たす最小の月
- カード作成日より前に締まったサイクルに属する backdate 利用は、スケジュール計算の対象外 (その分は carryoverBalance に含めて登録する仕様。カードフォームに注記)
- **使用枠** `utilization(T=today) = B₀ + Σ purchases(date ≤ T) − Σ due_M (paymentDate(M) ≤ T)`。構成上 ≥ 0
- 支払月 M の「目安」確定判定: `closed = today > closing(M−1)`

```ts
export type CardCycleInput = {
  closingDay: number; paymentDay: number;
  revolvingAmount: number | null; carryoverBalance: number;
  createdDate: string; // JST YYYY-MM-DD
};
export function cycleRange(card: CardCycleInput, paymentMonth: string): { fromExclusive: string; toInclusive: string };
export function cardPaymentSchedule(
  card: CardCycleInput,
  expenses: { date: string; amount: number }[],
  throughMonth: string, // この支払月まで計算 (M₁..throughMonth)
): { month: string; paymentDate: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }[];
export function cardUtilization(card: CardCycleInput, expenses: { date: string; amount: number }[], today: string): number;
```

例 (E-1) 一括・締め15・支払10・carryover 0・作成 2026-08-01、利用: 08-10 ¥3,000 / 08-20 ¥5,000:
→ M₁=2026-09 (mc=2026-08)。2026-09-10 支払 ¥3,000 (サイクル 07-15 exclusive .. 08-15 inclusive)、2026-10-10 支払 ¥5,000。

例 (E-2) リボ ¥10,000・締め31 (月末)・支払27・carryover ¥25,000・作成 2026-08-01、利用: 08-05 ¥8,000:
→ 09-27 ¥10,000 (B=23,000) → 10-27 ¥10,000 (B=13,000) → 11-27 ¥10,000 (B=3,000) → 12-27 ¥3,000 (B=0)。
utilization(2026-08-20) = 25,000 + 8,000 − 0 = 33,000。

### 4.4 定期ルールの materialize (支出 = サブスク・定額 / 収入 = 給与ルール。パターン適用の確定形)

v0.6 で定期ルールは**支出 (定額) と収入 (給与) の両方向**になった。テーブルは `recurring_rule` 1 本 + `direction` enum (§5。income_rule 別テーブルは不採用 §13-16)。materialize は方向に依らず同一ロジック。

`pattern/recurring-rule-materialize-unpaid-records` を適用。**「補充」と「再生成」は別操作** (gotcha/lazy-materialize-rolling-vs-edit-conflict の教訓を仕様に昇格):

| 操作 | トリガー | 何をするか |
|---|---|---|
| **補充 ensureMaterializedForUser(db, userId, now)** | 読み取り系 route の前段 middleware (§7 の対象 route 一覧) | 窓 = `currentMonth .. currentMonth+2` の 3 ヶ月。active な各 rule について `(sourceRuleId, yearMonth)` が**存在しない月だけ** INSERT (`onConflictDoNothing`)。既存 entry は編集有無・削除有無に関わらず**一切触らない**。当月の過去日 (rule 作成日より前の当月分含む) も生成する |
| **再生成 rematerializeRule(db, rule, now)** | rule の POST / PATCH (name, amount, dayOfMonth, cardId, category, active=true 化) 時のみ | 同一トランザクションで: 窓内の `sourceRuleId=rule.id AND date > today AND isManuallyEdited=false AND deletedAt IS NULL` を DELETE → 窓を再 INSERT (date > today の月のみ)。`date ≤ today` の entry と手動編集済み・ソフト削除済みは触らない |

生成される entry:
- direction=**expense**: `kind = rule.cardId != null ? 'card_expense' : 'expense'`、`cardId = rule.cardId`、`category = rule.category`
- direction=**income**: `kind = 'income'`、`incomeSource = 'salary'`、cardId/category は null
- 共通: `amount = rule.amount`、`date = clampDay(yearMonth, rule.dayOfMonth)`、`note = rule.name`、`sourceRuleId = rule.id`

規律 (両方向共通):
- **確定/予定は状態カラムを持たず日付から導出**: `date ≤ today` = 確定 (事実)、`date > today` = 予定。kinketsu の `paid` フラグは不採用 (§13-4)
- 生成 entry の手動 PATCH → `isManuallyEdited=true` を立て以後保護。**生成 entry の DELETE はソフト削除** (`deletedAt=now, isManuallyEdited=true`)。補充が「無い月だけ INSERT」なので、ハード削除すると復活する — ソフト削除行が unique を占有して復活を防ぐ。手動 entry (sourceRuleId=null) はハード DELETE
- rule DELETE: 同一トランザクションで (1) `date > today AND isManuallyEdited=false AND deletedAt IS NULL` の生成 entry を DELETE → (2) 残る生成 entry の `sourceRuleId` を null に (切り離し保持) → (3) rule 行 DELETE
- `active=false` 化: `date > today AND isManuallyEdited=false AND deletedAt IS NULL` の生成 entry を DELETE。補充は active な rule のみ対象
- id 安定性: 補充は既存に触らないので **GET を 2 回叩いても生成 entry の id は同一** (Reviewer 必須テスト)

### 4.5 税金目安 (純関数 `src/lib/tax.ts`。働き方 = freelance のみ)

JST 年 Y (Y ≤ 当年。当年は年初来、過去年は年全体):

```
businessIncomeYtd(Y)  = Σ entry(kind=income, incomeSource=salary, date ∈ [Y-01-01, min(today, Y-12-31)], deletedAt=null).amount
businessExpenseYtd(Y) = Σ entry(kind ∈ {expense, card_expense}, category=business, 同範囲, deletedAt=null).amount
profitYtd    = businessIncomeYtd − businessExpenseYtd
estimatedTax = floor(max(profitYtd, 0) × rate)                    // これまで分の税目安
monthsElapsed = Y が当年なら today の月番号 (8月→8)、過去年なら 12
monthlySetAside  = ceil(estimatedTax / monthsElapsed)             // 「毎月 取っておく目安」(税画面 hero)
annualProjection = monthlySetAside × 12                            // 「年間目安」(monthly と表示整合させるため ×12)
```

経費は v0.6 で **`business` カテゴリ**に統合した (isBusinessExpense フラグ廃止 §13-17)。monthlySetAside / annualProjection の定義は §14-7 判断点。

**概算率テーブル (v1 設計定数。所得税+住民税+国保込みのざっくり実効率。境界値は下側 bracket に含める)**:

```ts
export const TAX_BRACKETS: ReadonlyArray<{ maxProfit: number | null; rate: number }> = [
  { maxProfit: 1_000_000, rate: 0.15 },
  { maxProfit: 2_000_000, rate: 0.20 },
  { maxProfit: 4_000_000, rate: 0.25 },
  { maxProfit: 6_000_000, rate: 0.30 },
  { maxProfit: 10_000_000, rate: 0.35 },
  { maxProfit: null,       rate: 0.40 },
];
export function taxEstimate(profitYtd: number): { rate: number; amount: number };
```

例: profit 3,640,000 → rate 0.25 → estimatedTax 910,000。monthsElapsed=8 なら monthlySetAside = ceil(910,000/8) = 113,750、annualProjection = 1,365,000。profit 1,000,000 ちょうど → 0.15。profit ≤ 0 → rate 0.15・estimatedTax 0・monthlySetAside 0。
※ 率の数値は Touri 調整可 (§14-1)。**将来の精密計算への耐性は「率を DB に持たない + 収入/経費の生データ (日付・区分・実額) を落とさず保持する」ことで担保** — 控除・青色申告は user_settings への additive カラム追加 + tax.ts の差し替えで対応でき、entry スキーマの migration を要しない。

### 4.6 日次残高系列 (残高推移チャートの定義。純関数 `src/lib/homeSummary.ts`)

対象月 M の全日 d (1 日〜月末) について:

```
remainingAt(M, d) = Σ income(M, date ≤ d) − Σ cashExpense(M, date ≤ d) − Σ_c Σ_{m: paymentDate(c,m) ∈ M ∧ paymentDate ≤ d} due_{c,m}
```

- これは**口座残高ではなく月内キャッシュフロー累積** (月初 0 起点)。銀行残高は扱わない原則 (§13-11) と矛盾しない — 「月内の入出金を日付順に積んだ線」である
- **不変条件: remainingAt(M, 月末日) = remaining(M) (§4.2)**。全項が月スコープなので恒等。Reviewer は assert すること
- projected 判定: `d > today` → `projected: true`。過去月は全点 false、未来月は全点 true
- 予定の織り込み: materialize 済み定期 entry (支出・給与とも。ソフト削除済みは除外)・未来日付の手動 entry・カード支払 (paymentDate の日に due 全額)
- `minPoint` = 系列の最小値の点。同値が複数日あれば**最早日**
- **判定文言** (チャート下 + カード詳細で共通。表示はクライアント、値はサーバ): `minPoint.value ≥ 0` → 「支払いはすべて足りる見込み」(teal) / 負 → 「支払いに足りない日があります」(red)
- チャート上の**貯金目標ライン** = y = savingsGoal の teal 破線 + ラベル「貯金目標 ¥N」。savingsGoal=null なら描かない

```ts
export function buildDailySeries(input: {
  month: string; today: string;
  entries: { kind: "expense" | "income"; amount: number; date: string }[]; // 対象月・deletedAt=null。card_expense は渡さない (支払月で効かせる)
  cardPayments: { paymentDate: string; amount: number }[];                 // 対象月に支払日がある due (§4.3)
}): { series: { date: string; value: number; projected: boolean }[]; minPoint: { date: string; value: number } };
```

### 4.7 支払いイベント・支出内訳・支出の質 (純関数 `src/lib/calendar.ts` / `homeSummary.ts`)

**支払いイベント (カレンダー / ホーム「今後の支払い」)** — 対象月 M のイベント集合:

```
fixed_cost   : 生成 entry (direction=expense 由来 = kind ∈ {expense, card_expense}, sourceRuleId≠null, yearMonth=M, deletedAt=null)
card_payment : 各カードの支払月 M の due (§4.3。due=0 のカードは出さない)
salary       : 生成 entry (kind=income, sourceRuleId≠null, yearMonth=M, deletedAt=null)
```

- **手動 entry はイベントに出ない** (予定の管理対象はルール/カード由来のみ)
- `paymentCount` = fixed_cost 件数 + card_payment 件数 (salary は数えない)
- `paymentTotal` = Σ fixed_cost(cardId=null).amount + Σ card_payment.amount — **カード紐づき定額は引き落としに内包されるため合計から除外** (現金流出ベース。二重計上ガード。行としては「◯◯カードから」ラベルで表示する)。**§14-9 判断点** (モックの単純合算と違う)
- ホームの「今後の支払い」= 同集合のうち `type ∈ {fixed_cost, card_payment}` かつ `date > today` を date asc。表示は先頭 3 件 + フッタ「M月の残り支払い予定 (N件) ¥T」(N/T は同部分集合に paymentCount/paymentTotal と同じ規則を適用)

**支出内訳 (breakdown)** — 記録タブのドーナツ / ランキング:

```
breakdown(M) = category ごとの Σ entry(kind ∈ {expense, card_expense}, yearMonth=M, deletedAt=null).amount
```

- **利用月ベース** (card_expense は支払月でなく使った月に計上)。§4.2 の spending (支払月ベース) とは軸が違う — 「どこに使ったか」の表示専用であり、remaining の二重計上ではない
- `category = null` は `other` に合算。amount > 0 のカテゴリのみ、amount 降順。income は含めない

**支出の質 (fixed/variable)** — 記録タブ:

```
qualityFixed(M)    = Σ entry(kind ∈ {expense, card_expense}, sourceRuleId≠null, yearMonth=M, deletedAt=null).amount  // 削減しづらい固定費 = ルール由来
qualityVariable(M) = 同条件で sourceRuleId=null                                                                       // 削減できる変動費 = 手動入力
savingTip(M)       = floor(qualityVariable(M) / 10)   // 「変動費を1割削ると +¥N/月」
```

比率表示はクライアント: `fixedPct = round(fixed×100/(fixed+variable))`、`variablePct = 100 − fixedPct`。合計 0 なら両方 0 (バー非表示)。カテゴリ推定はしない (v1 の割り切り。削減ヒントも v1 スコープ外 §13-18)。

## 5. データモデル (Drizzle / Postgres。★本丸)

`src/db/auth-schema.ts` は `npx @better-auth/cli generate` 生成 (user / session / account / verification、provider pg)。以下は `src/db/schema.ts` (**export 名はこの通りにする**):

```ts
import { boolean, date, index, integer, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";
import { user } from "./auth-schema";

export const entryKindEnum = pgEnum("entry_kind", ["expense", "card_expense", "income"]);
export const incomeSourceEnum = pgEnum("income_source", ["salary", "other"]);
export const entryCategoryEnum = pgEnum("entry_category",
  ["food", "daily", "transport", "entertainment", "housing", "business", "health", "other"]);
export const employmentTypeEnum = pgEnum("employment_type", ["employee", "freelance", "part_time", "contract"]);
export const ruleDirectionEnum = pgEnum("rule_direction", ["expense", "income"]);

export const userSettings = pgTable("user_settings", {
  userId: text("user_id").primaryKey().references(() => user.id, { onDelete: "cascade" }),
  employmentType: employmentTypeEnum("employment_type").notNull(),
  savingsGoal: integer("savings_goal"),               // 月次貯金目標。null = 未設定
  // 将来の精密税計算 (申告区分・控除など) は additive カラムとしてここに足す
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const card = pgTable("card", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  name: text("name").notNull(),                       // 1..20 文字
  closingDay: integer("closing_day").notNull(),       // 1..31 (31 = 月末扱い)
  paymentDay: integer("payment_day").notNull(),       // 1..31
  revolvingAmount: integer("revolving_amount"),       // null = 一括
  creditLimit: integer("credit_limit"),               // null = 未設定
  carryoverBalance: integer("carryover_balance").notNull().default(0),
  createdDate: date("created_date", { mode: "string" }).notNull(), // 作成時の JST 日付 (サイクル起点 §4.3)
  archived: boolean("archived").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("card_user_idx").on(t.userId)]);

export const recurringRule = pgTable("recurring_rule", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  direction: ruleDirectionEnum("direction").notNull(), // expense = サブスク・定額 / income = 給与
  name: text("name").notNull(),                       // 1..30 文字
  amount: integer("amount").notNull(),                // ≥1
  dayOfMonth: integer("day_of_month").notNull(),      // 1..31 (月末クランプ)
  cardId: uuid("card_id").references(() => card.id, { onDelete: "restrict" }), // expense のみ。null = 現金/口座
  category: entryCategoryEnum("category"),            // expense のみ
  startMonth: text("start_month").notNull(),          // 作成時の currentMonthJst() をサーバが設定
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("recurring_rule_user_idx").on(t.userId)]);

export const entry = pgTable("entry", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  kind: entryKindEnum("kind").notNull(),
  amount: integer("amount").notNull(),                // 常に正。符号は kind から導出
  date: date("date", { mode: "string" }).notNull(),   // YYYY-MM-DD
  yearMonth: text("year_month").notNull(),            // date から書き込み時にサーバが導出 (index 用)
  category: entryCategoryEnum("category"),            // expense / card_expense のみ非 null 可。business = 経費 (freelance 限定)
  cardId: uuid("card_id").references(() => card.id, { onDelete: "restrict" }), // kind=card_expense で必須
  incomeSource: incomeSourceEnum("income_source"),    // kind=income で必須
  note: text("note"),                                 // ≤100 文字。生成 entry では rule.name のコピー
  sourceRuleId: uuid("source_rule_id").references(() => recurringRule.id, { onDelete: "set null" }),
  isManuallyEdited: boolean("is_manually_edited").notNull().default(false),
  deletedAt: timestamp("deleted_at", { withTimezone: true }), // 生成 entry のソフト削除 (§4.4)。手動 entry は常に null
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  uniqueIndex("entry_rule_month_uq").on(t.sourceRuleId, t.yearMonth)
    .where(sql`${t.sourceRuleId} is not null`),
  index("entry_user_month_idx").on(t.userId, t.yearMonth),
  index("entry_user_card_date_idx").on(t.userId, t.cardId, t.date),
]);
```

補足 (実装がここで迷わないための決め):
- **集計・一覧は常に `deletedAt IS NULL` でフィルタ**。unique index はソフト削除行も占有する (復活防止が目的)
- **経費はカテゴリ `business`** (v0.1 の isBusinessExpense フラグは廃止 §13-17)。税計算 (§4.5) と経費ゲート (§7.4) はカテゴリで判定
- 給与と同時入力した経費は独立した expense entry (category=business)。給与 entry とのリンク FK は持たない (§13-7)
- カテゴリは**固定 8 種 enum** (v0.6 で 経費 business / 住居 housing を追加、固定費 utilities を廃止)。ユーザー編集 CRUD なし (§13-6)。ラベル/アイコン/色の対応表は §9.6
- 「使用枠」「支払い目安」「今月の支出」「貯金見込み」は全て導出値。**テーブルに持たない** (カード支払 entry を作らない理由は §13-3)

## 6. 認証 (Sign in with Apple ネイティブ relay)

atender の稼働実装を正典として**そのまま移植**する (v1 は Apple のみ。Google/magic link/Resend は入れない):

- サーバ `src/auth.ts`: atender `auth.ts` から `normalizeApplePem` / `buildAppleClientSecret` / `getAppleProviderConfig` / `getAuth` lazy singleton + Proxy / `resetAuth` を**そのまま**移植。差分は (1) `prismaAdapter` → `drizzleAdapter(getDb(), { provider: "pg", schema: authSchema })`、(2) plugins は `[bearer()]` のみ、(3) socialProviders は apple のみ、(4) `advanced.crossSubDomainCookies` 削除 (web なし)。session: `expiresIn: 60*60*24*30, updateAge: 60*60*24`。`trustedOrigins = [BETTER_AUTH_URL]`
- Apple 設定は atender 同等: **Service ID + SIWA Key + 動的 client secret 生成** (`APPLE_TEAM_ID`/`APPLE_KEY_ID`/`APPLE_PRIVATE_KEY` (base64 p8) から ES256 JWT を同期生成)。`appBundleIdentifier: "net.appily.onikeiri"` — ネイティブ idToken の audience は bundle id (Researcher 確認済)
- `src/middleware/session.ts`: atender 版の drizzle 移植。`auth.api.getSession({ headers })` → だめなら Bearer/Cookie の raw token で session テーブル直引き (expired なら削除して 401)。**この DB fallback があるためテストは raw token を Bearer に載せられる** (gotcha/better-auth-bearer-plugin-token-format-coupling への既知対処)
- better-auth handler mount: `app.on(["POST", "GET"], "/api/auth/**", (c) => getAuth().handler(c.req.raw))`
- iOS: `AppleSignIn.swift` / `KeychainStore.swift` (service = `"net.appily.onikeiri.auth"`, account = `"session-token"`) / `AuthStore.swift` を atender から移植し、**Google / magic link / callback URL 系のメソッドを削除** (`signInWithApple(idToken:)` / `bootstrap()` / `signOut()` / `refreshMe()` / `handleUnauthorized()` のみ残す)。custom URL scheme は不要なので登録しない
- サインイン: iOS が `ASAuthorizationController` で identityToken 取得 → `POST /api/auth/sign-in/social` body `{"provider":"apple","idToken":{"token":"<jwt>"}}` → レスポンスヘッダ `set-auth-token` を Keychain 保存 → 以後 `Authorization: Bearer <token>`
- entitlements: `OniKeiri/OniKeiri.entitlements` に `com.apple.developer.applesignin = [Default]`
- **人手前提タスク (Phase 1 冒頭、Touri/Leader)**: Apple Developer portal で App ID `net.appily.onikeiri` (SIWA capability) + Service ID (例 `net.appily.onikeiri.signin`) を作成。SIWA Key は team 単位なので atender の既存 key 流用を第一候補、流用不可なら新規発行

## 7. API (Hono REST)

- ベース: `src/app.ts` の `export const app` (named export。テスト接続点)。`src/index.ts` は `migrate()` (drizzle-orm/node-postgres/migrator, `migrationsFolder: "./drizzle"`) → `serve({ fetch: app.fetch, port, hostname: "0.0.0.0" })`
- 認証: `/api/auth/**` と `/healthz` 以外の `/api/*` 全てに `sessionMiddleware`
- **ensureMaterialized middleware の対象 route** (この 7 つのみ。書き込み系には付けない): `GET /api/home`, `GET /api/entries`, `GET /api/cards`, `GET /api/cards/:id/detail`, `GET /api/recurring-rules`, `GET /api/calendar`, `GET /api/tax/estimate`
- validation: `@hono/zod-validator`。**リクエストの nullable フィールドは zod 側 `.nullish()`** で受ける (Swift 合成 Codable は nil キーを省略する — gotcha/swift-codable-omits-nil-vs-zod-nullable)
- 共通: 対象リソースが存在しないか他ユーザー所有 → 404。amount は `int().min(1).max(99_999_999)`。date は実在日付 (2026-02-30 → 400) かつ `2020-01-01..2035-12-31`

### 7.1 エラーモデル (有限集合。この表以外の code を実装が導入しない)

エラー封筒: `{ "error": { "code": string, "message": string } }` (`errorMiddleware` が `AppError` の status/code を読む。instanceof 判定漏れで 500 に潰さない — gotcha/hono-error-middleware-apperror-status)

| status | code | いつ |
|---|---|---|
| 400 | `VALIDATION_FAILED` | zod 不合格・クロスフィールド規則違反 (§7.4) |
| 401 | `UNAUTHORIZED` | token なし/無効/期限切れ |
| 403 | `FREELANCE_REQUIRED` | 働き方 freelance 以外で経費カテゴリ / 税 API に触った |
| 404 | `NOT_FOUND` | リソース不在 or 他ユーザー所有 |
| 409 | `CARD_IN_USE` | 参照が残るカードの DELETE |
| 500 | `INTERNAL` | 予期しない例外 |

`/api/auth/**` (better-auth handler) は better-auth 標準応答のままで本表の対象外。

### 7.2 エンドポイント一覧

```
GET    /healthz                       → 200 {"ok":true}   (認証なし)
POST/GET /api/auth/**                 → better-auth handler
GET    /api/me                        → { user: {id,name,email}, onboarded: boolean, settings: SettingsDto | null }
DELETE /api/me                        → 204 (user 行削除 → 全データ cascade。セッションも消える)
GET    /api/settings                  → SettingsDto        (未作成なら 404)
PUT    /api/settings                  → PutSettingsBody → upsert → 200 SettingsDto
GET    /api/home?month=YYYY-MM        → HomeResponse (§7.3。month 省略時 currentMonthJst)
GET    /api/entries?month=YYYY-MM     → EntriesResponse (entries: date asc, createdAt asc。month 必須)
POST   /api/entries                   → CreateEntryBody → 201 EntryDto
POST   /api/entries/salary            → CreateSalaryBody → 201 { income: EntryDto, expenses: EntryDto[] }
PATCH  /api/entries/:id               → UpdateEntryBody → 200 EntryDto
DELETE /api/entries/:id               → 204 (手動=ハード / 生成=ソフト §4.4)
GET    /api/cards                     → { cards: CardDto[] }   (archived 含む。CardDto に導出値入り)
POST   /api/cards                     → CreateCardBody → 201 CardDto
PATCH  /api/cards/:id                 → UpdateCardBody → 200 CardDto
DELETE /api/cards/:id                 → 204 / 409 CARD_IN_USE
GET    /api/cards/:id/detail?months=N → CardDetailResponse (N: 1..3, default 3)
GET    /api/recurring-rules?direction=expense|income → { rules: RecurringRuleDto[] } (direction 省略時 全部)
POST   /api/recurring-rules           → CreateRuleBody → 201 RecurringRuleDto
PATCH  /api/recurring-rules/:id       → UpdateRuleBody → 200 RecurringRuleDto
DELETE /api/recurring-rules/:id       → 204
GET    /api/calendar?month=YYYY-MM    → CalendarResponse (month 必須)
GET    /api/tax/estimate?year=YYYY    → TaxEstimateResponse (year 省略時 JST 今年。year > 今年 → 400)
```

### 7.3 zod スキーマ / レスポンス型 (`src/routes/` 内で定義、型は export)

```ts
export const ENTRY_CATEGORIES = ["food","daily","transport","entertainment","housing","business","health","other"] as const;
export const EMPLOYMENT_TYPES = ["employee","freelance","part_time","contract"] as const;

export const PutSettingsBody = z.object({
  employmentType: z.enum(EMPLOYMENT_TYPES),
  savingsGoal: z.number().int().min(1).max(99_999_999).nullish(),  // null/省略 = 未設定
});
export const CreateEntryBody = z.object({
  kind: z.enum(["expense", "card_expense", "income"]),
  amount: z.number().int().min(1).max(99_999_999),
  date: DateString,                                  // /^\d{4}-\d{2}-\d{2}$/ + 実在日付 + 範囲
  category: z.enum(ENTRY_CATEGORIES).nullish(),
  cardId: z.string().uuid().nullish(),
  incomeSource: z.enum(["salary", "other"]).nullish(),
  note: z.string().max(100).nullish(),
});
export const CreateSalaryBody = z.object({           // income(salary) + 経費 (category=business 強制) の複合入力
  amount: z.number().int().min(1).max(99_999_999),
  date: DateString,
  note: z.string().max(100).nullish(),
  expenses: z.array(z.object({
    amount: z.number().int().min(1).max(99_999_999),
    note: z.string().max(100).nullish(),
  })).max(20).default([]),
});
export const UpdateEntryBody = z.object({            // kind / cardId は不変 (§13-8)
  amount: z.number().int().min(1).max(99_999_999).optional(),
  date: DateString.optional(),
  category: z.enum(ENTRY_CATEGORIES).nullish(),
  incomeSource: z.enum(["salary", "other"]).optional(),
  note: z.string().max(100).nullish(),
});
export const CreateCardBody = z.object({
  name: z.string().min(1).max(20),
  closingDay: z.number().int().min(1).max(31),
  paymentDay: z.number().int().min(1).max(31),
  revolvingAmount: z.number().int().min(1).nullish(),
  creditLimit: z.number().int().min(1).nullish(),
  carryoverBalance: z.number().int().min(0).default(0),
});
export const UpdateCardBody = CreateCardBody.partial().extend({ archived: z.boolean().optional() });
export const CreateRuleBody = z.object({
  direction: z.enum(["expense", "income"]),
  name: z.string().min(1).max(30),
  amount: z.number().int().min(1).max(99_999_999),
  dayOfMonth: z.number().int().min(1).max(31),
  cardId: z.string().uuid().nullish(),               // direction=expense のみ
  category: z.enum(ENTRY_CATEGORIES).nullish(),      // direction=expense のみ
});
export const UpdateRuleBody = CreateRuleBody.omit({ direction: true }).partial().extend({ active: z.boolean().optional() });

export type SettingsDto = { employmentType: (typeof EMPLOYMENT_TYPES)[number]; savingsGoal: number | null };
export type EntryDto = {
  id: string; kind: "expense" | "card_expense" | "income"; amount: number;
  date: string; yearMonth: string; category: string | null; cardId: string | null;
  incomeSource: "salary" | "other" | null;
  note: string | null; sourceRuleId: string | null; isManuallyEdited: boolean;
};
export type DailyPoint = { date: string; value: number; projected: boolean };
export type CategoryBreakdownItem = { category: string; amount: number };  // §4.7。amount>0 のみ、降順
export type CalendarEvent =
  | { type: "fixed_cost"; entryId: string; name: string; date: string; amount: number;
      cardId: string | null; cardName: string | null; category: string | null }
  | { type: "card_payment"; cardId: string; cardName: string; date: string; amount: number;
      fromExclusive: string; toInclusive: string; closed: boolean }
  | { type: "salary"; entryId: string; name: string; date: string; amount: number };
export type CalendarResponse = {
  month: string; today: string;
  events: CalendarEvent[];        // date asc。§4.7 の集合
  paymentCount: number; paymentTotal: number;   // §4.7 (salary 除外 / カード紐づき定額は total から除外)
};
export type HomeResponse = {
  today: string; month: string;
  spendable: number;              // 今月あと使える額 = remaining − (savingsGoal ?? 0) (§4.2)
  remaining: number;              // 月末見込み =「貯金見込み」表示値
  income: number; spending: number;                    // hero foot「収入 − 支出・予定込み」
  cashExpense: number; cardPaymentDue: number; cardUsage: number;  // 内訳 (検証・診断用に返す)
  savingsGoal: number | null;
  dailySeries: DailyPoint[];      // 月の全日分 (§4.6)
  minPoint: { date: string; value: number };
  upcomingPayments: CalendarEvent[];  // 当月・date>today・type∈{fixed_cost,card_payment}、date asc (全件。UI は先頭 3 件表示)
  upcomingTotal: number;              // §4.7 の現金流出ベース合計 (date>today 部分)
  employmentType: (typeof EMPLOYMENT_TYPES)[number];
};
export type EntriesResponse = {
  entries: EntryDto[];
  breakdown: CategoryBreakdownItem[];                  // §4.7
  quality: { fixed: number; variable: number; savingTip: number };  // §4.7
};
export type CardDto = {
  id: string; name: string; closingDay: number; paymentDay: number;
  revolvingAmount: number | null; creditLimit: number | null; carryoverBalance: number;
  archived: boolean;
  utilization: number;                                 // §4.3 導出
  monthUsage: number;                                  // 今月利用 = Σ card_expense(yearMonth=当月, deletedAt=null)
  nextPayment: { month: string; paymentDate: string; amount: number; closed: boolean } | null; // 今日以降で最初の支払
};
export type CardDetailResponse = {
  card: CardDto;
  payments: { month: string; paymentDate: string; amount: number;
              fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }[];
              // 開始月 = max(currentMonthJst, M₁) から months ヶ月分、月昇順
  recentExpenses: EntryDto[];      // この cardId の entry (deletedAt=null)、date desc、最大 10 件
  linkedRules: RecurringRuleDto[]; // この cardId に紐づく active な expense rule
};
export type RecurringRuleDto = {
  id: string; direction: "expense" | "income"; name: string; amount: number; dayOfMonth: number;
  cardId: string | null; category: string | null; startMonth: string; active: boolean;
};
export type TaxEstimateResponse = {
  year: number; businessIncomeYtd: number; businessExpenseYtd: number;
  profitYtd: number; rate: number; estimatedTax: number;
  monthlySetAside: number; annualProjection: number;   // §4.5
};
```

サブスク一覧サマリー (今月合計 = Σ active expense rules.amount / 年間換算 = ×12 / 件数) と給与一覧はクライアントが `GET /api/recurring-rules` から計算する (専用 API なし)。

### 7.4 クロスフィールド規則 (400/403 の確定リスト)

1. `kind=card_expense` ⟺ `cardId` 必須。`kind≠card_expense` で cardId 指定 → 400
2. `kind=income` ⟺ `incomeSource` 必須。`kind≠income` で incomeSource 指定 → 400
3. `kind=income` で `category` 指定 → 400
4. `category=business` (経費) は `employmentType=freelance` が前提 → それ以外は **403 FREELANCE_REQUIRED** (entry の POST/PATCH、rule の POST/PATCH とも)
5. `cardId` が archived カード → 400 (既存 entry は影響なし)
6. `CreateSalaryBody.expenses` が 1 件以上 かつ 非 freelance → 403 FREELANCE_REQUIRED。作成される経費 entry の category はサーバが `business` を設定する (body で指定させない)
7. `carryoverBalance > 0` は一括カードでも可 (未払い残として初回支払に乗る §4.3)
8. 生成 entry の PATCH で `date` を変える場合、**同一 yearMonth 内のみ** (unique(sourceRuleId, yearMonth) 保護) → 違反 400
9. `UpdateCardBody` で `closingDay`/`paymentDay` を変えると全期間の支払スケジュール導出が変わる (履歴は持たないので遡って再計算される。仕様)
10. `direction=income` の rule で `cardId` または `category` が非 null → 400

## 8. 挙動仕様 (Reviewer のテスト根拠。○○のとき△△)

時刻依存の項目は**標本時刻**を併記する (Reviewer はその時刻で `vi.setSystemTime` / now 注入すること)。プロセス TZ は UTC でテストする (本番コンテナと同じ)。

### B-AUTH
1. Authorization ヘッダなしで `GET /api/home` → 401 UNAUTHORIZED
2. DB に存在しない token を Bearer で送る → 401
3. session テーブルに直接 INSERT した raw token を Bearer で送る → 200 (middleware の DB fallback 経路)
4. expiresAt 過去の session token → 401、かつその session 行が削除されている
5. `DELETE /api/me` → 204。以後同 token は 401。entry/card/rule/settings 行が 0 件 (cascade)

### B-SET (settings / onboarding / 働き方)
1. 新規ユーザーの `GET /api/me` → `onboarded: false, settings: null`
2. `PUT /api/settings {employmentType:"freelance"}` → 200 `{employmentType:"freelance", savingsGoal:null}`。以後 `GET /api/me` → `onboarded: true`
3. `PUT` は upsert (2 回目は更新)。`GET /api/settings` は行が無ければ 404。`savingsGoal: null` 送信で目標解除
4. employmentType を freelance → employee に変えても既存の category=business entry は変わらない。以後 `GET /api/tax/estimate` は 403、新規の business カテゴリ entry/rule も 403
5. employee/part_time/contract の v1 挙動差は**無い** (freelance だけが経費 + 税を有効化する。他はラベル表示のみ)

### B-ENT (entries)
1. `POST /api/entries` kind=expense, amount=1200, date=today → 201。EntryDto の yearMonth が date の月、isManuallyEdited=false, sourceRuleId=null
2. amount=0 / 負値 / 1 億超 → 400。date="2026-02-30" → 400。date="2019-12-31" → 400
3. §7.4 の 1,2,3,5 の違反ケース → 400。4,6 → 403 FREELANCE_REQUIRED
4. 他ユーザーの entry を GET/PATCH/DELETE → 404
5. `GET /api/entries?month=2026-08` は 2026-08 の entry のみを date asc で返す。ソフト削除済みは含まない
6. 手動 entry の DELETE → 204、行が物理削除される
7. freelance で `POST /api/entries` kind=expense, category=business → 201 (経費として税集計に乗る B-TAX-4)

### B-SAL (給与 + 経費同時入力)
1. freelance で `POST /api/entries/salary {amount: 300000, date, expenses: [{amount: 20000}, {amount: 5000}]}` → 201。income 1 件 (incomeSource=salary) + expense 2 件 (**category=business がサーバ付与**) が**同一トランザクション**で作られる
2. expenses 内の 1 件が validation 違反なら**全体が 400 で 1 件も作られない**
3. 非 freelance + expenses=[] → 201 (純粋な給与収入として通る)。非 freelance + expenses 1 件以上 → 403
4. 作成された income と expense に相互リンクは無い (独立 entry。個別に PATCH/DELETE できる)

### B-MAT (定期ルール materialize: 支出・給与共通) — 標本時刻: now = 2026-08-20T03:00:00Z (= JST 2026-08-20 12:00)
1. `POST /api/recurring-rules {direction:"expense", name:"Netflix", amount:1490, dayOfMonth:5}` → 201、直後に entry が 3 件 (2026-08-05, 09-05, 10-05。kind=expense, note="Netflix", sourceRuleId=rule.id)。**08-05 は過去日だが生成される** (事実)
2. cardId 付き expense rule → 生成 entry は kind=card_expense + cardId 付き → カードのサイクル集計 (B-CARD) に自動で乗る
3. `direction:"income", name:"給与 (本業)", amount:280000, dayOfMonth:25` → 生成 entry は kind=income, incomeSource=salary, cardId/category=null。income(M) と税の businessIncomeYtd に乗る
4. `dayOfMonth: 31` の rule、窓に 2027-02 が入る時刻 (now = 2026-12-20T03:00:00Z) → 2027-02 分の date は **2027-02-28**
5. **id 安定**: `GET /api/entries?month=2026-09` を 2 回叩き、生成 entry の id が完全一致 (毎アクセス再生成の禁止)
6. rule PATCH (amount 1490→1990): date > today の未編集生成 entry (09-05, 10-05) が新 amount で作り直され、**08-05 (過去) は 1490 のまま**
7. 生成 entry (09-05) を PATCH amount=990 → isManuallyEdited=true。その後 rule PATCH amount=2490 しても 09-05 は 990 のまま (10-05 は 2490 になる)
8. 生成 entry (09-05) を DELETE → 204 (ソフト削除)。`GET /api/entries?month=2026-09` に出ない。**その後の GET でも復活しない**。DB 上は行が残り deletedAt≠null
9. rule PATCH `active: false` → 09-05, 10-05 (未編集・未来) が消える。08-05 は残る。`active: true` に戻す → 09-05, 10-05 が再生成される
10. rule DELETE → 未来未編集の生成 entry 削除、過去/編集済/ソフト削除済は sourceRuleId=null で残る、rule 行が消える
11. 月が進んだら補充: now を 2026-09-01T03:00:00Z に進めて GET → 2026-11 分が新規生成される (窓 M..M+2)
12. 同時リクエスト 2 本が補充を走らせても unique + onConflictDoNothing で二重生成されない (直列で 2 回呼んで件数不変、で代替検証可)

### B-CARD — 標本時刻: now = 2026-08-20T03:00:00Z (JST 2026-08-20)
1. §4.3 例 E-1 の入力で `GET /api/cards/:id/detail?months=3` → payments: 2026-09 due=3000 (closed=true: closing(2026-08)=08-15 < today)、2026-10 due=5000 (closed=false)、2026-11 due=0
2. §4.3 例 E-2 (リボ) の入力 → 09:10000 / 10:10000 / 11:10000 と balanceAfter 23000/13000/3000。utilization(08-20)=33000
3. 締め日 31・支払日 31 のカード、2027-02 の支払 → paymentDate=2027-02-28、サイクル=(2026-12-31, 2027-01-31]
4. カード作成 2026-08-18・締め 15: mc=2026-09 (closing(08)=08-15 < 作成日) → 初回支払月 2026-10。08-10 に backdate した利用はどの支払にも入らない (仕様 §4.3)
5. `GET /api/cards` の CardDto: nextPayment = 今日以降で最初の paymentDate の due (0 利用・carryover 0 なら amount=0)。monthUsage = 当月 card_expense 合計
6. `GET /api/cards/:id/detail` の recentExpenses は該当 cardId の entry を date desc 最大 10 件、linkedRules は cardId 一致の active expense rule のみ
7. entry または rule が参照するカードの DELETE → 409 CARD_IN_USE。参照ゼロなら 204
8. archived=true のカード: 新規 card_expense / rule 作成は 400 (§7.4-5)、既存 entry と支払スケジュール計算は継続
9. `months=4` → 400 VALIDATION_FAILED (1..3)

### B-HOME — 標本時刻: now = 2026-08-20T03:00:00Z
1. §4.2 の式通り (E-3): income 300,000 / cashExpense 45,000 / cardPaymentDue 18,000 / savingsGoal 100,000 → remaining=237,000, spendable=137,000, spending=63,000。cardUsage は remaining に影響しない
2. savingsGoal=null → spendable == remaining
3. カード 0 枚・rule 0 件・entry 0 件 → spendable=remaining=0, dailySeries 全日 value=0, upcomingPayments=[], upcomingTotal=0
4. 支出が収入を超えると remaining / spendable は負のまま返る (クランプしない)
5. upcomingPayments: 当月の fixed_cost (生成 entry) + card_payment のうち date > 2026-08-20 のみ、date asc。**salary イベントと過去日 (08-05 の定額など) は入らない**。upcomingTotal はカード紐づき定額を除いた現金流出ベース (§4.7)
6. 給与ルールの生成 entry (08-25 ¥280,000) は income(M) に入り、remaining を +280,000 する
7. `month=2026-07` (過去月) 指定 → その月の値で同式。today は常に現在
8. ensureMaterialized が home でも走る (rule 作成後 GET /api/home だけ叩いても dailySeries / upcomingPayments に定期分が織り込まれる)

### B-CHART (日次系列) — 標本時刻: now = 2026-08-20T03:00:00Z
1. dailySeries は 2026-08-01〜08-31 の 31 点 (欠落日なし)。date ≤ 2026-08-20 の点は projected=false、それより後は true
2. **不変条件: 最終点 (08-31) の value = HomeResponse.remaining** (§4.6)
3. 給与ルール生成 300,000 (08-25)・定額 cash 1,490 (08-27, 生成 entry)・カード支払 due 18,000 (paymentDate 08-10) のみのとき、系列は 08-01〜09: 0 / 08-10〜24: −18,000 / 08-25〜26: 282,000 / 08-27〜31: 280,510。minPoint = { date: "2026-08-10", value: −18000 } (同値最早日)
4. 3 の状態から 08-27 の生成 entry を DELETE (ソフト削除) → 再取得した系列で 08-27 以降が 282,000 になる (予定の削除が系列から消える)
5. 判定文言 (クライアント表示): minPoint.value ≥ 0 → 「支払いはすべて足りる見込み」(teal) / 負 → 「支払いに足りない日があります」(red)
6. `month=2026-07` → 全点 projected=false。`month=2026-09` → 全点 projected=true
7. 貯金目標ラインは savingsGoal 値の水平線 (クライアント描画)。savingsGoal=null → 非表示

### B-CAL (支払いカレンダー) — 標本時刻: now = 2026-08-20T03:00:00Z
1. 現金定額 (家賃 1日) + カード定額 (Netflix 15日, 楽天) + 給与ルール (25日) + 楽天カード (支払日 27日, due>0) があるとき `GET /api/calendar?month=2026-08` → events に fixed_cost 08-01 (cardId=null)、fixed_cost 08-15 (cardId≠null, cardName="楽天カード")、salary 08-25、card_payment 08-27 (cycle 範囲付き) が date asc で並ぶ
2. paymentCount = 3 (fixed_cost 2 + card_payment 1。salary は数えない)。paymentTotal = 家賃 + card_payment due (**Netflix はカード紐づきなので total から除外**)
3. due=0 のカードは card_payment イベントを出さない
4. ソフト削除済み生成 entry・手動 entry は events に出ない
5. `month` 省略 → 400 VALIDATION_FAILED。過去月・未来月 (窓 M..M+2 内) は指定可。窓外の未来月 (M+3 以降) は定期 entry が未生成のため fixed_cost/salary が空になり得る (仕様。カレンダー UI は M±1 の遷移のみ提供)

### B-QUAL (支出内訳・支出の質) — 標本時刻: now = 2026-08-20T03:00:00Z
1. breakdown は kind ∈ {expense, card_expense} を**利用月**で集計 (card_expense は支払月でない)。category=null は other に合算、amount>0 のみ降順、income は含まれない
2. `GET /api/entries?month=2026-08` の breakdown は同月の entry 集合に対する §4.7 の定義通り
3. quality: 生成 entry (sourceRuleId≠null) 合計が fixed、手動 entry 合計が variable。income と ソフト削除済みは両方に入らない
4. 例: 生成 82,000 + 手動 53,200 → quality = { fixed: 82000, variable: 53200, savingTip: 5320 } (floor(53200/10))
5. 支出 entry が 0 件 → quality = { fixed: 0, variable: 0, savingTip: 0 } (クライアントはバー非表示)

### B-TAX — 標本時刻: now = 2026-08-20T03:00:00Z
1. 非 freelance で `GET /api/tax/estimate` → 403 FREELANCE_REQUIRED
2. salary income 1,800,000 + 経費 0 (年内) → rate=0.20, estimatedTax=360,000, monthlySetAside=ceil(360000/8)=45,000, annualProjection=540,000
3. profit がちょうど 1,000,000 → rate=0.15 (境界は下側 bracket)
4. incomeSource=other の収入は businessIncomeYtd に入らない。category≠business の支出は businessExpenseYtd に入らない。card_expense も category=business なら経費に入る (利用日ベース)
5. expense が income を超え profit<0 → estimatedTax=0, rate=0.15, monthlySetAside=0
6. 集計は date ∈ [2026-01-01, 2026-08-20] (YTD)。2026-08-25 の未来日付 entry は入らない
7. `year=2025` → その年の 1/1〜12/31 全体、monthsElapsed=12。`year=2027` (未来) → 400 VALIDATION_FAILED

### B-TZ (暦の危険窓) — サーバプロセス TZ=UTC で実行
1. now = 2026-08-31T22:00:00Z (= JST 2026-09-01 07:00) のとき `GET /api/home` の today="2026-09-01"、month="2026-09"。**UTC の暦 (8/31) に引き摺られない**
2. 同時刻で materialize 窓は 2026-09..2026-11 (2026-08 は補充対象外だが既存 08 分は消えない)
3. now = 2026-12-31T16:00:00Z (= JST 2027-01-01 01:00) → tax estimate の year は 2027、profitYtd は 0 から再スタート、monthsElapsed=1

## 9. UI/UX (正典 = mock v0.6。トークン・骨格をここに固定)

### 9.1 デザイントークン (`OniKeiri/Core/Design/DS.swift` — 数値ハードコード散らし禁止。v0.6 確定値)

```swift
enum DS {
    enum Palette {   // v0.6 サーフェス。ライト固定 (§14-8)
        static let bg = Color(hex: 0xFFFFFF)          // 画面背景
        static let bgSoft = Color(hex: 0xF5F6F5)      // ピル/アイコン地/バー地
        static let line = Color(hex: 0xEFEFF1)        // カード border・区切り線
        static let cell = Color(hex: 0xF4F4F5)        // カレンダー月外セル
        static let text = Color(hex: 0x17181A)
        static let textSub = Color(hex: 0x8E9097)
        static let ink = Color(hex: 0x121316)         // 黒 (選択ピル/FAB/primary ボタンの塗り、固定費バー)
        static let teal = Color(hex: 0x2E9E8F)        // ★ positive/判定/リンク/トグル ON/給与タイル
        static let tealSoft = Color(hex: 0xE7F3F0)    // teal 系アイコン地
        static let red = Color(hex: 0xE60033)         // ブランドアバターと負値・警告のみ (アクセントには使わない)
        static let heroTeal = Color(hex: 0x6FD3C5)    // 黒ヒーロー上の teal 文字 (貯金見込み)
    }
    enum Grad {      // 黒ヒーロー / 黒サマリー / カード券面
        // linear 150deg #17181C → #26272C の上に、右上 (x:0.82, y:0.18) の radial ハイライト rgba(255,255,255,0.10)→透明 (半径 55%) を重ねる
        // 実装: ZStack(LinearGradient + RadialGradient) を ViewModifier `dsInkSurface(radius:)` として提供
    }
    enum Chart {     // カテゴリ色 (§9.6 が対応表) + チャート
        static let cat1 = Color(hex: 0xE60033); static let cat2 = Color(hex: 0xFF9500)
        static let cat3 = Color(hex: 0x5856D6); static let cat4 = Color(hex: 0x34C759)
        static let cat5 = Color(hex: 0x00A8C6); static let cat6 = Color(hex: 0x8E8E93)
        static let cat7 = Color(hex: 0xAF52DE); static let cat8 = Color(hex: 0xA2845E)  // cat7/cat8 はパレット外追加 (§14-3)
        static let grid = Color(hex: 0xEEEEF0)        // グリッド線 (v0.6 実値)
        static let projected = Color(hex: 0xB9BCC4)   // 予測線 (破線) の色
        static let minDot = Color(hex: 0xFF9500)      // 最低残高ドット
    }
    enum Typo {  // 8+1 段トークン (確定値を維持。mock CSS は ±1-2px の縮小値だがトークン表を正とする — §14-10)
        // display  40pt / .bold      — Home hero のみ
        // displayS 34pt / .bold      — サブ画面 (サブスク/税金) の黒サマリー主数値
        // amountL  26pt / .bold      — カード内主数値
        // amountM  17pt / .semibold  — リスト金額
        // title    19pt / .bold      — 画面タイトル
        // heading  14pt / .semibold  — カード見出し (textSub 色で控えめに)
        // body     15pt / .regular
        // caption  12pt / .medium
        // labelS   11pt / .medium
    }   // 実装は static let display = Font.system(size: 40, weight: .bold) 形式 + @ScaledMetric で Dynamic Type 追従
    enum Radius {
        static let hero: CGFloat = 24     // 黒ヒーロー/黒サマリー
        static let card: CGFloat = 18     // 白カード・カード券面
        static let tile: CGFloat = 12     // サービスタイル/行アイコン/キーパッドキー
        // ピル/チップ/FAB/ボタンは Capsule (999)
    }
    enum Spacing {
        static let screenMargin: CGFloat = 16   // 画面左右 (v0.6 実値)
        static let cardPadding: CGFloat = 16
        static let gridGap: CGFloat = 10        // クイック/機能グリッド gap
        static let sectionGap: CGFloat = 14     // カード間 (v0.6 は 12-14。14 に統一)
    }
}
```

- weight は 400/500/600/700 の 4 つ (v0.6 トークンで 500 が正式化)。**全数値は tabular-nums** (`.monospacedDigit()`)
- 白カードは **border 1px `line`・影なし**。黒面 (`dsInkSurface()`) は hero・サブ画面サマリー・カード券面。単色 ink 塗りは選択ピル/FAB/primary ボタン
- **teal がアクセント**: 収入 `+` 金額・判定 OK・リンクボタン (「カレンダーで見る ›」)・トグル ON・給与タイル。**red は禁欲的に**: ブランドアバター「鬼」と負値/警告 (`-¥N`、税額、判定 NG) のみ。ボタン塗りに red を使わない
- 金額共通部品 `YenText(amount: Int, style: YenText.Style, positive: Bool = false)`、`Style` = `.display` / `.displayS` / `.amountL` / `.amountM`。書式 `¥300,000`、負値 `-¥12,000` + red。収入文脈 (`positive: true`) は `+¥120,000` + teal
- **サービスタイル** `ServiceTile(initial: String, color: Color, size: ServiceTile.Size)` (.regular 36pt/radius 12、.small 24pt/radius 8): ルール名の頭文字 1 字を白字で載せた角丸正方形。**色はルールのカテゴリ色 (§9.6)、direction=income は teal** (モックのサービスブランド色は v1 不採用 §13-19)
- dark: **v1 はライト固定** (`UIUserInterfaceStyle: Light`)。mock が dark palette を定義していないため独自導出をしない (HIG の OS 追従原則からの逸脱 — §14-8)
- コントラスト: text #17181A on #FFF ≈ 16:1。白 on ink ≈ 17:1。teal #2E9E8F on 白 = 3.3:1 — **本文サイズの単独テキストには使わない** (金額 semibold・リンク 600・給与タイル白字のみ = 大きめ/太字 3:1 用途)。textSub #8E9097 on 白 = 3.5:1 → caption 以下の補助情報のみ。タップターゲット 44pt 以上 (モックの 38pt 円ボタンは当たり判定を 44pt に拡張)
- アイコンは SF Symbols 単一セット (モックの手書き stroke アイコンは対応する SF Symbols に置換。weight .medium で統一)

### 9.2 IA / ナビ構造 (§5 観点: 対等コンテキスト 3 つ → bottom tab。機能は「ホーム = ハブ」から push)

**3 タブ** (`TabView`。key = accessibilityIdentifier):

| key | ラベル | SF Symbol (選択時 fill) |
|---|---|---|
| `tab-home` | ホーム | `house` / `house.fill` |
| `tab-records` | 記録 | `list.bullet` |
| `tab-settings` | 設定 | `person` / `person.fill` |

タスク頻度 → 動線表 (頻度根拠: 出費の意識化が大目的 → 記録と残額確認が最頻):

| タスク | 頻度 | 動線 | タップ数 (到達) |
|---|---|---|---|
| 残額・貯金見込みを見る | 毎日 | 起動 → ホーム hero | 0 |
| 支出/収入/クレカ支出を記録 | 毎日 | ホーム → クイック 3 → テンキー | 1 |
| 記録を見返す・内訳/質を見る | 週数回 | 記録タブ | 1 |
| 今後の支払いを確認 | 週1 | ホーム「今後の支払い」(常時可視) / カレンダー | 0-1 |
| サブスク/カード/給与/税金の管理 | 月1以下 | ホーム機能グリッド → push | 1-2 |
| 働き方・貯金目標の変更 | 稀 | 設定タブ | 1-2 |

push 階層は最大 2 段 (ホーム → カード一覧 → カード詳細)。現在地は nav タイトル + 戻るボタンで明示。

### 9.3 ホームタブ (v0.6 の並び。視覚階層: L0 = hero 主数値 / L1 = クイック・今後の支払い・チャート / L2 = 機能グリッド / L3 = meta)

```
┌──────────────────────────────┐
│ (鬼)  2026年8月               │ ← header: red アバター + 年月 (title) + 「あと N 日」(caption)
│       あと25日                │    ※ モックの通知ベルは v1 非表示 (機能が無い §13-20)
│ ┌─ 黒ヒーロー ──────────────┐ │
│ │ 今月あと使える額           │ │ ← caption (白 62%)
│ │ ¥137,000                  │ │ ← L0 display。spendable (§4.2)。負値は red
│ │ 収入−支出・予定込み  貯金見込み│ ← labelS (白 55%)
│ │ ¥300,000 − ¥163,000 ¥237,000│ ← amountM。右 = remaining (heroTeal 色)
│ └───────────────────────────┘ │
│ [↓支出] [↑収入] [▤クレカ支出] │ ← クイックアクション 3 (白カード枠) → 入力モーダル
│ (⟳)   (▤)   (¥)   (▦)        │ ← 機能グリッド 4 (bgSoft 角丸アイコン + labelS)
│ サブスク・定額 カード 給与 税金目安│    → 各一覧へ push。非 freelance は税金非表示で 3 件
│ ┌ 今後の支払い ─ カレンダーで見る ›┐ ← 白カード。teal リンク → CalendarView
│ │ 8/15 [N] Netflix 楽天カードから ¥1,490│ ← 直近 3 件 (upcomingPayments 先頭 3)
│ │ 8/27 [▤] 楽天カード 引き落とし ¥… ›│ ← card_payment 行は tap → CardDetailView (sub = サイクル範囲「7/16〜8/15 利用分」)
│ │ 8月の残り支払い予定 (N件)      ¥T │ ← フッタ (件数 + upcomingTotal)
│ └───────────────────────────────┘ │
│ ┌ 残高推移 ── 8月末まで ────────┐ │
│ │  実線→(today)‥‥破線予測       │ │ ← BalanceLineChart (§10.4)。貯金目標 teal 破線 + minPoint 橙ドット
│ │ ● 最低残高 8/24 — 支払いはすべて│ │
│ │   足りる見込み        ¥64,300  │ │ ← 判定行 (§4.6 の文言)
│ └───────────────────────────────┘ │
└──────────────────────────────┘
   [ホーム]   [記録]   [設定]
```

- クイックアクション (key = accessibilityIdentifier): `quick-expense` 支出 (`arrow.down`) / `quick-income` 収入 (`arrow.up`) / `quick-card` クレカ支出 (`creditcard`) → EntrySheet を該当 segment で開く
- 機能グリッド: `feature-subs` サブスク・定額 (`arrow.trianglehead.2.clockwise.rotate.90`) → SubsListView / `feature-cards` カード (`creditcard`) → CardsListView / `feature-salary` 給与 (`banknote`) → SalaryListView / `feature-tax` 税金目安 (`chart.bar`) → TaxView (**freelance のみ表示**)
- 「今後の支払い」: 0 件なら行の代わりに caption「この先の支払い予定はありません」。カード紐づき定額行は sub「◯◯カードから」
- 状態: loading = hero 部 ProgressView + カード類は空枠 placeholder。error = hero 部短文 + 再試行。entry 0 件 = チャート value 0 実線 + 「支払いはすべて足りる見込み」。カード 0 枚で `quick-card` → シート内 empty state「カードを登録してください」+ [カードを追加] (CardFormSheet へ)

### 9.4 入力モーダル (EntrySheet) — sheet 1 枚。v0.6: セグメント切替式

- 上から: grabber / **セグメント 3** (`segment-expense` 支出 / `segment-income` 収入 / `segment-card` クレカ支出 — ink 塗り Capsule が選択) / 金額表示 (`.display` を最大 38pt 縮小許容) / **カテゴリチップ横スクロール** (支出・クレカ支出のみ。§9.6 の 8 種。`business` チップは freelance のみ表示。既定 = `food`) / **カードチップ** (クレカ支出のみ。既定 = 前回使用カード UserDefaults `"lastCardId"`) / **収入 segment のみ**: incomeSource チップ (給与/その他、既定 その他) + freelance かつ 給与選択時「経費も同時に入力」展開 (経費行の追加 UI 最大 20 件 → 確定時 `POST /api/entries/salary`) / 日付チップ (既定 today、tap で inline DatePicker) / **テンキー** (1-9, 00, 0, ⌫。キー高 52pt) / 確定ボタン (ink 塗り Capsule「追加する」、amount=0 disabled)
- 編集モード (`editing: EntryDto`): セグメント非表示 (kind 不変)、削除ボタン (red text) を下部に追加
- Cancel = swipe-dismiss + 背景 tap (入力途中なら confirmationDialog)

```swift
enum EntrySegment: String, CaseIterable { case expense, income, cardExpense }
struct EntrySheet: View {
    init(initialSegment: EntrySegment,
         cards: [CardDto],            // 非 archived のみ
         employmentType: EmploymentType,
         today: String,               // HomeResponse.today
         editing: EntryDto?,          // nil = 新規
         onSubmit: @escaping (EntrySubmission) async -> Bool)  // true = 閉じる
}
enum EntrySubmission {
    case create(CreateEntryBodyDto)
    case createSalary(CreateSalaryBodyDto)
    case update(id: String, UpdateEntryBodyDto)
    case delete(id: String)
}
struct AmountInput: Equatable {       // テンキーの純ロジック (XCTest 対象)
    private(set) var digits: String = ""      // 先頭 0 禁止、最大 8 桁 (超過タップは無視)
    var amount: Int { Int(digits) ?? 0 }
    mutating func tap(_ key: KeypadKey)       // KeypadKey: .digit(Int) / .doubleZero / .backspace
}
```

### 9.5 記録タブ・設定タブ・push 画面 (v0.6 骨格)

- **記録タブ (RecordsView)**: (1) 月スイッチャ `‹ 2026年8月 ›` → (2) **フィルタピル** `filter-all` すべて / `filter-expense` 支出 / `filter-income` 収入 / `filter-card` クレカ (kind のクライアント側フィルタ) → (3) **今月の支出内訳カード** (heading + 合計 amountL、CategoryDonutChart 104pt + CategoryRankingList。breakdown 表示、**フィルタ非適用**) → (4) **支出の質カード** (StackedQualityBar + 凡例「削減しづらい固定費 N% / 削減できる変動費 N%」+ insight 行「変動費を1割削ると +¥N/月」(teal)) → (5) 日別リスト (日付降順セクション `8月6日 木`)。行 = カテゴリ icon (色 §9.6) or ServiceTile (生成 entry) + note/カテゴリラベル + カード badge (card_expense) + 金額 (income は `+` teal)。swipe delete / tap → EntrySheet(editing:)。空 = `ContentUnavailableView("まだ記録がありません", systemImage: "tray")` (内訳・質カード非表示)。**削減ヒントカードは v1 では出さない** (§13-18)
- **設定タブ (SettingsView)** — ユーザー自身の情報のみ: (1) アカウント行 (red アバター + user.name + 「Apple ID でログイン中」) (2) 働き方セクション: 働き方 row (現在値表示 → WorkStylePickerSheet 4 択: 会社員/個人事業主/アルバイト・パート/契約・派遣) + 「経費入力・税金目安」row (**表示専用トグル**: freelance ⟺ ON、disabled) (3) 目標セクション: 貯金目標 row (¥N or 未設定 → SavingsGoalSheet: テンキー + 「目標を解除」) (4) ログアウト (テキストボタン) (5) アカウント削除 (red text、confirmationDialog 2 段 → DELETE /api/me。モックに無いが App Store 要件で必須)
- **CalendarView** (push): 月グリッド (曜日ヘッダ 日=red/土=#3478F6、月外セル = cell 色、today = ink 丸数字)。イベント日に ServiceTile .small (定額 = カテゴリ色 / 給与 = teal「給」/ card_payment = 黒ミニ券面)。1 日に複数は最大 2 個 + 「+N」。下部「M月の支払い予定 (paymentCount 件)」リスト: 合計行 (paymentTotal) + イベント行 (card_payment 行は tap → CardDetailView)。月遷移 ‹ › は M±1 のみ
- **SubsListView** (push): 黒サマリー (今月の定額支払い displayS = Σ active expense rules.amount / 年間換算 = ×12 / 登録数) → ソートピル (`sort-day` 請求日 = dayOfMonth asc 既定 / `sort-high` 高い順 / `sort-low` 安い順 / `sort-card` カード別 — クライアントソート) → ルール行 (ServiceTile + name + 「毎月N日・カード名 or 現金/口座」+ ¥N/月 + ›) tap → RuleFormSheet (編集)。inactive はセクション分離「停止中」。**FAB ＋** (ink 丸 54pt、右下 sticky) → RuleFormSheet (新規, direction=expense)
- **CardsListView** (push): カード行 (黒ミニ券面 42×28 + name + 「締め N日 / 支払い N日」(31 は「月末」表記) + monthUsage「今月利用」+ ›) → CardDetailView。下部 ghost ボタン (line 枠 Capsule)「＋ カードを追加」→ CardFormSheet
- **CardDetailView** (push): 黒券面 (aspect 1.62、name / 「締め日 N日・支払日 N日・リボ ON/OFF」/ 「使用 ¥N / 限度 ¥N」+ 白トラックバー = utilization/creditLimit、limit null なら金額のみ) → 「来月の支払い目安」カード (nextPayment.amount を amountL + status 行「M/D に支払い予定・(§4.6 の判定文言)」) → 「最近のクレカ支出」(recentExpenses) → 「紐づく定額支出」(linkedRules + sub「自動でクレカ支出に計上」)。nav 右に編集 → CardFormSheet
- **CardFormSheet**: name / 締め日 Picker (1-31、31 は「月末」表記) / 支払日 Picker / リボ (トグル + 月額) / 限度額 (任意) / 現在の未払い残高 carryoverBalance (注記「アプリ登録前の未払い分・リボ残高を入れてください」) / (編集時) アーカイブトグル + 削除 (参照ありは 409 → アーカイブを案内)
- **SalaryListView** (push): income rule 行 (ServiceTile teal「給」+ name + 「毎月N日・自動計上」+ ¥N + ›) tap → RuleFormSheet (direction=income)。ghost「＋ 給与を追加」。footnote「臨時収入・不定期の入金はホームの「収入」から都度追加できます。個人事業主では給与入力時に経費も同時に登録できます」
- **RuleFormSheet**: `init(direction: RuleDirection, existing: RecurringRuleDto?, cards: [CardDto], onSubmit:)`。共通 = name / 金額テンキー / 毎月の支払日 Picker。expense のみ = 支払いカード (なし=現金/口座) + カテゴリチップ。(編集時) 停止トグル + 削除
- **TaxView** (push, freelance のみ到達): 黒サマリー (「毎月 取っておく目安」displayS = monthlySetAside / 年間目安 = annualProjection / 概算率 = rate%) → 「今年の見込み (1月〜今日)」カード: 事業収入 / 経費 / 利益 (課税所得ざっくり) / 税金の目安 (estimatedTax、red、sub「所得税+住民税+国保」) → footnote「概算率による目安です。実際の納付額は確定申告で決まります」
- **Onboarding**: サインイン直後 `onboarded=false` なら全画面 1 枚「働き方を教えてください」4 択 (→ PUT /api/settings)。スキップ不可
- **SignInView**: ロゴ + `SignInWithAppleButton` (ブランド規約準拠、自前スタイル禁止 — library/signin-button-branding 参照)

### 9.6 カテゴリ対応表 (enum 値 = API 文字列 = accessibilityIdentifier。全件明示。色 = DS.Chart)

| value | ラベル | SF Symbol | 色 | 入力チップ |
|---|---|---|---|---|
| `food` | 食費 | `fork.knife` | cat1 `#E60033` | ○ (既定) |
| `daily` | 日用品 | `basket` | cat8 `#A2845E` (追加色 §14-3) | ○ |
| `transport` | 交通 | `tram` | cat2 `#FF9500` | ○ |
| `entertainment` | 娯楽 | `gamecontroller` | cat4 `#34C759` | ○ |
| `housing` | 住居 | `house` | cat3 `#5856D6` | ○ (モックのチップ列に無いが追加 §14-3) |
| `business` | 経費 | `briefcase` | cat5 `#00A8C6` | freelance のみ |
| `health` | 医療 | `cross.case` | cat7 `#AF52DE` (追加色 §14-3) | ○ |
| `other` | その他 | `ellipsis.circle` | cat6 `#8E8E93` | ○ |

mock v0.6 のランキング配色 (住居=cat3 / 食費=cat1 / 経費=cat5 / 交通=cat2 / 娯楽=cat4) と一致させている。

### 9.7 チェック観点の残項 (ui-ux-design-perspectives §7)

- 状態網羅: 各画面の loading / error / empty は §9.3-9.5 に記載。権限系は freelance ゲート (税/経費) のみで、非 freelance では入口自体を出さない
- a11y: 44pt / コントラスト §9.1 / Dynamic Type (@ScaledMetric)。teal・textSub の使用域制限は §9.1 に明記
- 現在地明示: タブ強調 + nav タイトル + 戻る。push は最大 2 段
- 数値の逸脱: カスタム 9 段タイポの採用理由は §9.1 (v0.6 承認値)。ライト固定は §14-8

## 10. iOS 実装契約 (Codex 向け確定シグネチャ)

### 10.1 project.yml (atender 流用の差分)

- `name: OniKeiri` / `bundleIdPrefix: net.appily` / `PRODUCT_BUNDLE_IDENTIFIER: net.appily.onikeiri` / deploymentTarget iOS 17.0 / `SWIFT_VERSION: 6.0` / `SWIFT_STRICT_CONCURRENCY: minimal` / `TARGETED_DEVICE_FAMILY: 1` / `developmentLanguage: ja` / `DEVELOPMENT_TEAM: 2J3HYGP2K8` / `CODE_SIGN_STYLE: Automatic`
- **packages なし** (SPM 0 = オフラインビルド可)
- Info.plist properties: `UILaunchScreen: {}` / `ITSAppUsesNonExemptEncryption: false` / `CFBundleDevelopmentRegion: ja` + `CFBundleLocalizations: [ja]` / **`UIUserInterfaceStyle: Light`** (§9.1 ライト固定) / `ONIKEIRI_API_SCHEME` `ONIKEIRI_API_HOST` (xcconfig 変数経由。Debug=`http`/`localhost:8787` + `NSAppTransportSecurity.NSAllowsLocalNetworking: true`、Release=`https`/`onikeiri.appily.run`) / `CFBundleShortVersionString: "1.0"` / `CFBundleVersion: "1"`
- **Info.plist は手編集禁止** (xcodegen が毎回再生成。版数の正典は project.yml — gotcha/xcodegen-info-plist-regenerated-every-run)
- targets: `OniKeiri` (app) / `OniKeiriTests` (unit)。UITests target は v1 では作らない

### 10.2 Core 型

```swift
// APIConfig.swift
enum APIConfig {
    static var baseURL: URL { get }          // Info.plist の SCHEME/HOST から組む (atender 方式)
    static let apiSession: URLSession
}

// APIError.swift (atender 移植)
enum APIError: Error, Equatable {
    case unauthorized
    case api(status: Int, code: String, message: String)
    case http(status: Int)
    case transport(String)
    case decoding(String)
}
struct ErrorResponse: Codable { struct Inner: Codable { let code: String; let message: String }; let error: Inner }

// DTO.swift — §7.3 の TS 型と 1:1。nullable は全て Optional
enum EntryKind: String, Codable { case expense, cardExpense = "card_expense", income }
enum IncomeSource: String, Codable { case salary, other }
enum EntryCategory: String, Codable, CaseIterable { case food, daily, transport, entertainment, housing, business, health, other }
enum EmploymentType: String, Codable, CaseIterable { case employee, freelance, partTime = "part_time", contract }
enum RuleDirection: String, Codable { case expense, income }
struct SettingsDto: Codable, Equatable { let employmentType: EmploymentType; let savingsGoal: Int? }
struct EntryDto: Codable, Identifiable, Equatable {
    let id: String; let kind: EntryKind; let amount: Int; let date: String; let yearMonth: String
    let category: EntryCategory?; let cardId: String?; let incomeSource: IncomeSource?
    let note: String?; let sourceRuleId: String?; let isManuallyEdited: Bool
}
struct DailyPointDto: Codable, Equatable { let date: String; let value: Int; let projected: Bool }
struct MinPointDto: Codable, Equatable { let date: String; let value: Int }
struct CategoryBreakdownDto: Codable, Equatable, Identifiable {
    let category: EntryCategory; let amount: Int          // null カテゴリはサーバ側で other に畳み済み
    var id: String { category.rawValue }
}
enum CalendarEventDto: Codable, Equatable, Identifiable {  // "type" キーで分岐する手書き init(from:) / encode(to:)
    case fixedCost(entryId: String, name: String, date: String, amount: Int, cardId: String?, cardName: String?, category: EntryCategory?)
    case cardPayment(cardId: String, cardName: String, date: String, amount: Int, fromExclusive: String, toInclusive: String, closed: Bool)
    case salary(entryId: String, name: String, date: String, amount: Int)
    var id: String { get }   // fixedCost/salary = entryId、cardPayment = "\(cardId)-\(date)"
    var date: String { get }
}
struct HomeResponse: Codable, Equatable { /* §7.3 と同名フィールド (spendable/remaining/savingsGoal/dailySeries/minPoint/upcomingPayments/upcomingTotal/employmentType 含む) */ }
struct EntriesResponse: Codable, Equatable {
    struct Quality: Codable, Equatable { let fixed: Int; let variable: Int; let savingTip: Int }
    let entries: [EntryDto]; let breakdown: [CategoryBreakdownDto]; let quality: Quality
}
struct CardDto: Codable, Identifiable, Equatable { /* §7.3 と同名 (utilization/monthUsage/nextPayment 含む)。NextPayment は nested struct */ }
struct CardDetailResponse: Codable, Equatable { /* card / payments / recentExpenses / linkedRules */ }
struct RecurringRuleDto: Codable, Identifiable, Equatable { /* §7.3 と同名 */ }
struct CalendarResponse: Codable, Equatable { /* month / today / events / paymentCount / paymentTotal */ }
struct TaxEstimateResponse: Codable, Equatable { /* §7.3 と同名 (monthlySetAside / annualProjection 含む) */ }

// APIClient.swift
@MainActor final class APIClient {
    init(auth: AuthStore, session: URLSession = APIConfig.apiSession)
    func home(month: String?) async throws -> HomeResponse
    func entries(month: String) async throws -> EntriesResponse
    func createEntry(_ body: CreateEntryBodyDto) async throws -> EntryDto
    func createSalary(_ body: CreateSalaryBodyDto) async throws -> SalaryResponseDto
    func updateEntry(id: String, _ body: UpdateEntryBodyDto) async throws -> EntryDto
    func deleteEntry(id: String) async throws
    func cards() async throws -> [CardDto]
    func createCard(_ body: CardFormBodyDto) async throws -> CardDto
    func updateCard(id: String, _ body: CardUpdateBodyDto) async throws -> CardDto
    func deleteCard(id: String) async throws
    func cardDetail(id: String, months: Int) async throws -> CardDetailResponse
    func recurringRules(direction: RuleDirection?) async throws -> [RecurringRuleDto]
    func createRule(_ body: RuleFormBodyDto) async throws -> RecurringRuleDto
    func updateRule(id: String, _ body: RuleUpdateBodyDto) async throws -> RecurringRuleDto
    func deleteRule(id: String) async throws
    func calendar(month: String) async throws -> CalendarResponse
    func taxEstimate(year: Int?) async throws -> TaxEstimateResponse
    func settings() async throws -> SettingsDto
    func putSettings(_ body: SettingsDto) async throws -> SettingsDto
    func deleteAccount() async throws
}
// 全メソッド: 401 → APIError.unauthorized を throw し、呼び元の共通ハンドラが auth.handleUnauthorized()
```

Body 系 Dto (`CreateEntryBodyDto` 等) は §7.3 zod と同フィールドの Encodable struct。**nil は JSON キー省略で送る** (合成 Codable のまま。サーバ zod が `.nullish()` なので整合)。

### 10.3 App 構造 / 状態管理

```swift
@MainActor @Observable final class RefreshTicker { private(set) var tick = 0; func bump() { tick += 1 } }
@MainActor @Observable final class AppEnvironment {
    let auth: AuthStore; let api: APIClient; let ticker: RefreshTicker
}
```

- 状態管理は **画面ごとの @Observable ViewModel + RefreshTicker** の最小構成。mutation 成功時に `ticker.bump()` → 各画面は `.task(id: env.ticker.tick) { await load() }` で再取得。クライアント側キャッシュ層は作らない (§13-9)
- RootView: `auth.state` で分岐 — `.unknown` → ProgressView / `.signedOut` → SignInView / `.signedIn` → `me.onboarded == false` なら Onboarding、それ以外 MainTabView (3 タブ §9.2)
- 画面 View 名 (Features/ 配下): `HomeView` / `RecordsView` / `SettingsView` / `CalendarView` / `SubsListView` / `CardsListView` / `CardDetailView` / `SalaryListView` / `TaxView` / `EntrySheet` / `RuleFormSheet` / `CardFormSheet` / `WorkStylePickerSheet` / `SavingsGoalSheet` / `OnboardingView` / `SignInView`
- DEBUG ビルドは env `ONIKEIRI_UI_TEST_BEARER_TOKEN` があれば起動時に Keychain へ save してログインスキップ (atender の AppEnvironment `#if DEBUG` 方式)

### 10.4 チャート・共通部品契約 (Swift Charts。`OniKeiri/Core/Design/` 配下)

```swift
import Charts   // Swift Charts (iOS 17 で全 API 利用可。SectorMark も iOS 17+)

struct BalanceLineChart: View {
    init(series: [DailyPointDto], minPoint: MinPointDto, savingsGoal: Int?)
    // 描画規則:
    // - LineMark 2 系列: actual (projected=false, ink 実線 2.4pt) / projected (DS.Chart.projected 破線 StrokeStyle(lineWidth: 2, dash: [4, 5]))。
    //   境界の連続性のため projected 系列は最後の actual 点を先頭に含めて描く
    // - actual 系列の下に AreaMark (ink 14% → 透明のグラデ)
    // - today 位置に縦 RuleMark (ink 12%) + 実線終端に PointMark (白丸 + ink 縁)
    // - savingsGoal != nil → RuleMark(y:) を teal 破線 (dash [5,4], opacity 0.7) + annotation「貯金目標 ¥N」(labelS, teal)
    // - minPoint の位置に PointMark (DS.Chart.minDot)
    // - チャート下判定行: 「最低残高 M/D — <§4.6 の判定文言>」(caption, textSub) + YenText(.amountM)
    // - accessibilityIdentifier: "balance-chart"
}
struct CategoryDonutChart: View {
    init(breakdown: [CategoryBreakdownDto])
    // SectorMark(angle: .value) + innerRadius: .ratio(0.72)、幅 104pt。色は §9.6 (DS.Chart)。
    // breakdown 空 → グレー円 (DS.Chart.cat6, opacity 0.3) + caption「記録がありません」
}
struct CategoryRankingList: View {
    init(breakdown: [CategoryBreakdownDto])
    // 行 = 色ドット 7pt + ラベル (caption semibold) + 金額 + 相対バー (高さ 4pt Capsule, bgSoft 地)
    //   バー幅比 = amount / breakdown.first.amount (§4.7 で降順保証)
}
struct StackedQualityBar: View {
    init(fixed: Int, variable: Int)
    // 高さ 12pt Capsule を ink (fixed) / teal (variable) で分割。合計 0 なら非表示。
    // 凡例とパーセント (§4.7 の丸め規則) は呼び出し側 (RecordsView) が描く
}
struct ServiceTile: View {
    enum Size { case regular /* 36pt, r12 */, small /* 24pt, r8 */ }
    init(initial: String, color: Color, size: Size)   // ルール名頭文字 1 字 + カテゴリ色 (§9.1)
}
```

## 11. テスト基盤 (実行分担を含む)

### 11.1 フレームワークと配置

| 対象 | フレームワーク | 配置 | 実行コマンド |
|---|---|---|---|
| API 純ロジック (tz/money/cardSchedule/tax/materialize 純関数/homeSummary/calendar/zod) | vitest (`unit` project, DB 不要) | `apps/api/tests/unit/` | `pnpm -C apps/api test:unit` |
| API 統合 (route + DB。挙動仕様 B-* の主戦場) | vitest (`api` project) | `apps/api/tests/api/` | `pnpm -C apps/api test:api` |
| 型検査 | `tsc --noEmit` | — | `pnpm -C apps/api typecheck` |
| iOS ロジック (AmountInput / DTO decode (CalendarEventDto の type 分岐含む) / YenText 書式 / カテゴリ対応表) | XCTest | `apps/ios/OniKeiriTests/` | `xcodebuild test -project OniKeiri.xcodeproj -scheme OniKeiri -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'` |

### 11.2 実行担当の分担 (Codex sandbox は network 遮断で DB を叩けない)

| 実行者 | 回せる範囲 |
|---|---|
| **Codex (実装ループ内)** | `typecheck` + `test:unit` + iOS ビルド/XCTest (SPM 依存ゼロなのでオフライン可) |
| **Claude (Reviewer/Leader)** | 上記全部 + **`test:api`** (`docker compose -f apps/api/docker-compose.test.yml up -d` で Postgres 起動 → 実行) + シミュレータ実操作スクショ |

Reviewer への指示: **DB 依存テスト (B-AUTH/B-SET/B-ENT/B-SAL/B-MAT/B-CARD/B-HOME/B-CHART/B-CAL/B-QUAL/B-TAX/B-TZ) を Codex に「実行済み」と報告させない**。Codex の「テスト不能」「既存破損」報告は独立検証してから受理 (PJ 規約)。

### 11.3 テスト DB / セットアップ

- `docker-compose.test.yml`: `postgres:16-alpine`、port `54329`、db `onikeiri_test`
- `.env.test`: `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54329/onikeiri_test`、`BETTER_AUTH_SECRET=test-secret`、`BETTER_AUTH_URL=http://localhost:8787`。APPLE_* は未設定 (→ `getAppleProviderConfig()` が null を返し apple provider 無効。auth 構成はそれで正常起動する)
- `tests/setup/global.ts` (api project の globalSetup): drizzle `migrate()` を**テスト側で明示実行** (index.ts は import しないので migration は自動で走らない — gotcha/vitest-server-setup-must-migrate-app-db)。各テストファイルの beforeEach で業務テーブル + user/session を TRUNCATE
- vitest.config.ts で `.env.test` を明示ロードし、**dev の `.env` を読み込まない** (gotcha/dev-dotenv-leaks-into-vitest)。`src/env.ts` は import 時 parse をしない lazy getter (gotcha/env-module-import-time-parse)
- 認証ヘルパ: `tests/setup/auth.ts` に `createTestUser(db): Promise<{ userId: string; token: string }>` — user + session 行を drizzle で直接 INSERT し raw token を返す (middleware の DB fallback 経路 §6 で通る。signed cookie 偽造は不要)
- app 接続点: `import { app } from "../../src/app"` → `app.request(path, init)` (パス明示 — gotcha/design-must-specify-app-export-path)

### 11.4 Reviewer 必須の観点 (このドメイン固有)

1. **生成 entry の id 安定** (B-MAT-5): GET 2 回 → id 一致 assert
2. **ソフト削除の非復活** (B-MAT-8): DELETE → GET → 不在 → もう一度 GET → 不在
3. 時刻依存は §8 の標本時刻で `vi.setSystemTime`、プロセス TZ=UTC
4. 例示値 (E-1, E-2, E-3, B-CHART-3) と式 (§4) が食い違ったら**式が規範** (gotcha/design-doc-example-values-can-contradict-formula)。**mock v0.6 内の金額・%・件数は装飾値であり検証対象にしない**
5. カレンダーの二重計上ガード (B-CAL-2): カード紐づき定額が paymentTotal に入らないこと

## 12. デプロイ (Phase 1 で本番疎通まで)

- Coolify: appily SKILL 標準フロー。managed **Postgres** リソースを先に作成 (dandan-app 実例) → `DATABASE_URL` は Coolify 内部ネットワーク URL
- app 作成 (Public Repo build pack, repo `ait913/oni-keiri` public, dockerfile `apps/api/Dockerfile`, build context = repo root) → 作成直後に `is_force_https_enabled=false` を PATCH (redirect loop 防止) → fqdn `https://onikeiri.appily.run`
- Dockerfile: `node:20-slim` + corepack pnpm → workspace install (`--filter @oni-keiri/api`) → `tsc` build → `drizzle/` を dist と共にコピー → CMD `node dist/index.js` (起動時 migrate)。`.dockerignore` に `.git`
- ヘルスチェック: `health_check_host` を `127.0.0.1` にする (Node は IPv6 `::1` に bind しない — gotcha/coolify-healthcheck-localhost-ipv6)。path `/healthz`
- env: `DATABASE_URL` / `BETTER_AUTH_SECRET` / `BETTER_AUTH_URL=https://onikeiri.appily.run` / `APPLE_CLIENT_ID` (Service ID) / `APPLE_APP_BUNDLE_ID=net.appily.onikeiri` / `APPLE_TEAM_ID=2J3HYGP2K8` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY` (**base64 単一行**で格納 — normalizeApplePem が復号) / `PORT=8787`
- TestFlight (Phase 2): atender/CLAUDE.md の CLI 手順 (archive → exportArchive → altool) をそのまま流用。ASC API キーは既存 `AuthKey_973AZ487M3.p8`。ASC 側の新規 App レコード作成 (bundle `net.appily.onikeiri`) は人手タスク

## 13. 不採用案 (再検討ループ防止)

1. **Apple dummy client secret での省略構成**: ネイティブ idToken 検証だけなら secret 未使用の可能性があるが**未実証**。atender で実証済みの Service ID + SIWA Key + 動的 secret 生成を採る
2. **RRULE / on-the-fly 展開**: 月次固定のみ・件数小・予測が core → materialize が優位 (pattern/recurring-rule-materialize-unpaid-records の判断軸そのまま)
3. **カード支払いを entry として materialize**: 支払額はカード利用の導出値。実体化すると card_expense を 1 件足すたびに支払 entry の再集計・編集競合・二重計上リスクを抱える。read-time 計算 (純関数) に固定
4. **kinketsu 式 `paid` フラグ**: 「確定操作」の手数が鬼シンプルに反する。サブスク/給与は自動発生で日付到来=事実 → 確定/予定は date と today の比較で導出。編集保護は isManuallyEdited のみで成立
5. **生成 entry のハード DELETE**: rolling 補充 (無い月だけ INSERT) と両立せず削除が復活する → ソフト削除 (deletedAt) で unique を占有させる
6. **カテゴリのユーザー CRUD**: 管理画面・並び順・削除時の孤児処理が UI/API を太らせる。固定 8 enum (§14-3 で Touri 確認)
7. **給与⇄経費のリンク FK**: 税計算は年次集計で足り、リンクは編集/削除の整合コストだけ増える。独立 entry で十分
8. **entry の kind / cardId の PATCH 可変**: 種別変更は集計の再解釈が多い割に頻度が低い。削除→再作成で足りる
9. **クライアント側キャッシュ層 (TanStack 移植等)**: 画面数が少なく全データがサーバ集計済み。RefreshTicker + 再取得で十分 (標準部品優先の裁定にも整合)
10. **2 タブ / 4 タブ以上**: v0.6 で 3 タブ確定 (設定 = ユーザー情報のみを独立させ、機能はホームをハブに push)。機能別タブ乱立は頻度に合わない
11. **銀行残高・月跨ぎ繰越の追跡**: 口座残高の初期値入力と補正 UX が必要になり「鬼シンプル」から外れる。v1 は月内完結の remaining/spendable に限定 (§14-5)
12. **SQLite**: 確定技術決定 (Postgres + Drizzle) に従う。managed Postgres で Volume mount / バックアップ手当が不要になる
13. **cron による materialize**: 個人アプリに cron インフラは過剰。lazy (アクセス時補充) で足りる (pattern 準拠)
14. **recurring_rule の endMonth**: 解約 = active OFF で表現できる。カラムを増やさない
15. **fastlane / Prisma / 手動テーマトグル / UITests target**: 各正典・裁定・v1 スコープにより不使用
16. **income_rule 別テーブル (給与ルールの独立実装)**: entry.sourceRuleId の FK が 2 本に割れ、unique 制約と materialize の補充/再生成を二重実装することになる。`recurring_rule.direction` の 1 テーブルなら FK 1 本・materialize 1 実装で、方向差は生成 entry の kind/incomeSource だけに閉じる
17. **isBusinessExpense フラグ (v0.1 設計)**: v0.6 モックで経費が入力チップ = カテゴリとして確定。フラグとカテゴリの二重表現は「経費かつ食費」を許すが、v1 の税計算は事業経費の総額しか使わないため不要。カテゴリ `business` に一本化
18. **削減ヒント (使っていないサブスク検出・前月比アラート)**: **v1 では出さない。レコメンドロジック (利用実績の推定・前月比較) は別設計に切り出す**。モックの当該カードは雰囲気のみ
19. **サービスタイルのブランド色 (Netflix 赤等)**: 色の手動指定 UI かブランド辞書が要る。v1 はカテゴリ色で代替 (タイル頭文字で識別は足りる)
20. **通知 (ホームのベルアイコン)**: v1 に通知機能はない → ベル自体を出さない。支払日リマインド通知は将来の別設計
21. **taxEstimate を /api/home に同梱 (v0.2 設計)**: v0.6 ホームに税表示が無い。税は TaxView が `/api/tax/estimate` を直接叩く

## 14. Touri が承認ゲートで見る判断点 (Leader がエスカレーション時に提示)

1. **税概算率テーブル** (§4.5) の 6 段の数値 — 設計定数であり Touri の肌感で調整可能
2. **締め日 (closingDay) の必須入力** — 要望の列挙外だが、支払日だけでは請求サイクルが決まらないため追加した
3. **カテゴリ再編 (8 種)** — v0.6 で 経費 `business`・住居 `housing` を追加し 固定費 `utilities` を廃止。入力チップにモックに無い「住居」を足した。色はパレット 6 色に対し実数 8 のため `#AF52DE` (医療) / `#A2845E` (日用品) をパレット外から追加
4. **リボ/未払い残高の初期値 (carryoverBalance)** をカード登録フォームに置く UX
5. **「月内完結」原則** — 残額・貯金見込みは月内キャッシュフローで閉じ、銀行残高・繰越は扱わない
6. **hero「今月あと使える額」= remaining − 貯金目標** — 目標を先取りした後の可処分額と定義し、「貯金見込み」(= remaining) と数値を分けた。モックの装飾数値はこの区別を示していないため要確認
7. **税金の「毎月 取っておく目安」= ceil(これまでの税目安 ÷ 経過月数)、年間目安 = ×12** — モックの見た目 (毎月 = 年間/12) を、経過月ベースで取り置き不足が出ない定義に置き直した
8. **v1 はライトモード固定** — mock v0.6 が dark palette を定義していないため独自導出せず `UIUserInterfaceStyle: Light`。dark はモック拡張後に別途 (HIG の OS 追従原則からの意図的逸脱)
9. **支払い合計は現金流出ベース** — カレンダー/ホームの合計からカード紐づき定額を除外 (カード引き落としに内包され二重計上になるため。モックの単純合算と違う)
10. **タイポトークンの ±1-2px** — mock v0.6 の CSS 実値 (amount-l 24px 等) より、承認済みトークン表 (26pt 等) を正とした
