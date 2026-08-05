# 鬼個人経理 (oni-keiri) — プロジェクト固有メモ

親規約: [Muraki/CLAUDE.md](../../CLAUDE.md)

## プロジェクト要約

個人向けの「鬼シンプル」経理アプリ。家計簿 + クレカ支払い管理 (支払日/リボ/限度額/来月目安) + 定額支出 (サブスク) + 給与登録を 1-2 タブで扱う。個人事業主モード ON で経費入力と税金目安 (v1 は概算率ベース) が有効化される。

## 主要ドキュメント

- 設計書: `.designs/<YYYYMMDD>-<feature-slug>.md` (Architect が作成)
- プロジェクト固有ナレッジ: `.knowledge/<topic>.md`

## 技術スタック

- Mobile: Swift / SwiftUI (iOS ネイティブ)
- Backend: Hono + TypeScript
- DB: Postgres (Drizzle)
- 認証: Sign in with Apple → Better Auth (ネイティブ token relay パターン)
- ホスティング: Appily レーン (Coolify)、配布は TestFlight

## 規約・やらないこと

- **エンジン構成 (この PJ の裁定、2026-08-06 Touri)**: トークン節約のため **Developer 実装・レビューループ・モック生成は `codex exec` 主体**。Researcher/Architect と統合判断は Claude。Codex 利用時は `knowledge/tool-quirk/codex-behavior.md` 必読、成果は必ず git/ファイル実体で検証。Codex の否定的主張 (「既存破損」「テスト不能」) は独立検証してから受理
- UI はミニマル・アイコンボタンベース。基本機能へ最長 2 タップ。ベンチマークは PayPay
- デザインシステムを設計 doc で先に確定し、UI の手戻りを作らない
- 税金計算 v1 は目安ざっくり (概算率)。ただし DB は将来の精密計算 (控除・青色申告) に耐える設計にする

## 主要ワークフロー

(環境構築が進み次第、ライブで追記: デプロイ手順 / TestFlight upload / マイグレーション)

## デプロイ / 外部リソース

- URL: (未作成 — appily.run サブドメイン予定)
- Coolify app uuid: (未作成)
