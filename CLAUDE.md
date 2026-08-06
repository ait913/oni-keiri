# 鬼個人経理 (oni-keiri) — プロジェクト固有メモ

親規約: [Muraki/CLAUDE.md](../../CLAUDE.md)

## プロジェクト要約

個人向けの「鬼シンプル」経理アプリ。家計簿 + クレカ支払い管理 (支払日/リボ/限度額/来月目安) + 定額支出 (サブスク) + 給与登録を 1-2 タブで扱う。個人事業主モード ON で経費入力と税金目安 (v1 は概算率ベース) が有効化される。

## 主要ドキュメント

- **設計 doc (正典)**: `.designs/20260806-v1-foundation.md` — Touri 承認済 (2026-08-06)。DB/API/挙動仕様/デザインシステム/Phase 分割すべてここ
- **UI モック (正典)**: `.designs/20260806-mock-v0.6.html` — 白地+黒ヒーロー+ティール、3 タブ + ホーム機能ハブ
- プロジェクト固有ナレッジ: `.knowledge/<topic>.md`

## 技術スタック

- Mobile: Swift / SwiftUI (iOS ネイティブ)
- Backend: Hono + TypeScript
- DB: Postgres (Drizzle)
- 認証: Sign in with Apple → Better Auth (ネイティブ token relay パターン)
- ホスティング: Appily レーン (Coolify)、配布は TestFlight

## 規約・やらないこと

- **エンジン構成 (この PJ の裁定、2026-08-06 Touri)**: トークン節約のため **Developer 実装・レビューループ・モック生成は `codex exec` 主体**。Researcher/Architect と統合判断は Claude。Codex 利用時は `knowledge/tool-quirk/codex-behavior.md` 必読、成果は必ず git/ファイル実体で検証。Codex の否定的主張 (「既存破損」「テスト不能」) は独立検証してから受理
- UI の正典は `.designs/20260806-mock-v0.6.html` (白地+黒ヒーロー+ティール、赤はブランドと負値警告のみ)。3 タブ (ホーム/記録/設定)、機能はホームのハブからアクセス、記録系は 1 タップでモーダル
- プロダクト軸: 「キャッシュフロー管理 → 日常出費の意識 → 金銭的余裕」。機能の優先度はこの軸で判断
- 税金計算 v1 は目安ざっくり (概算率)。ただし DB は将来の精密計算 (控除・青色申告) に耐える設計にする

## 主要ワークフロー

### サーバのテストを回す

```
cd apps/api
docker compose -f docker-compose.test.yml up -d --wait   # test Postgres (port 54329)
pnpm exec tsc --noEmit
pnpm exec vitest run    # DB 依存テスト込み。fileParallelism=false 前提 (共有DB+TRUNCATE)
```

### デプロイする

push しても自動デプロイはされない。Coolify API で明示的に:
```
curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" "$COOLIFY_API_BASE/deploy?uuid=sshwwljmwdw4wtmrc2pziyl5&force=false"
# 確認: curl https://onikeiri.appily.run/healthz → {"ok":true}
```
migration はコンテナ起動時に自走 (index.ts が drizzle migrate を実行)。

### TestFlight に上げる (atender 手順の流用)

```
cd apps/ios; xcodegen generate
xcodebuild archive -project OniKeiri.xcodeproj -scheme OniKeiri -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/OniKeiri.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_973AZ487M3.p8 \
  -authenticationKeyID 973AZ487M3 -authenticationKeyIssuerID a3955ee4-936a-4c78-b9d1-9d1c559885af
xcodebuild -exportArchive -archivePath build/OniKeiri.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates (同上の鍵引数)
xcrun altool --upload-app -f build/export/OniKeiri.ipa -t ios \
  --apiKey 973AZ487M3 --apiIssuer a3955ee4-936a-4c78-b9d1-9d1c559885af
```

- 出力は pipe に通さずファイルに落とす (バッファでハング判別不能になる)
- codesign 無言ハング時: `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db`
- 版数の正典は project.yml の info.properties (Info.plist 手編集禁止)
- **2026-08-07 時点: archive/export まで成功済 (App ID net.appily.onikeiri は自動登録済)。upload は ASC の app レコード作成待ち**

### iOS をビルドする

```
cd apps/ios
xcodegen generate
xcodebuild -project OniKeiri.xcodeproj -scheme OniKeiri -destination 'platform=iOS Simulator,name=iPhone 16' test
```
Info.plist は project.yml から再生成されるので手編集禁止。

## デプロイ / 外部リソース

- URL: https://onikeiri.appily.run
- Coolify app uuid: `sshwwljmwdw4wtmrc2pziyl5` (**現在 branch=feature/v1-foundation を向いている。main マージ後に git_branch を PATCH で main に戻すこと**)
- Coolify Postgres uuid: `yfk5ppgsc0f0hsh0zj3kz2g1` (onikeiri-pg, postgres:17-alpine)
- env: `APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY` は **PLACEHOLDER のまま** — Touri の Apple ポータル作業 (App ID + Services ID `net.appily.onikeiri.web` + SIWA Key) 完了後に差し替え
- 関連 SKILL: appily
