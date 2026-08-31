# CalendarCountdown · カレンダーカウントダウン

> Appleカレンダーを信頼できる唯一の情報源として使い、ユーザー、ウィジェット、AIエージェントに見やすく持ち運べるカウントダウン機能を提供する、macOSネイティブの重要日トラッカーです。

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## スクリーンショット

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="CalendarCountdown メインウィンドウのデモ">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="CalendarCountdown デスクトップウィジェットのデモ">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="CalendarCountdown メニューバーのデモ">
</p>

> 画像内のカレンダー、人物名、日付はすべて架空のデモデータで、実際のユーザー情報は含まれていません。

## このプロジェクトについて

CalendarCountdownは別のカレンダーデータベースではありません。アカウント、カレンダー、予定、色は引き続きAppleカレンダーが管理します。本プロジェクトはEventKitを通じてユーザーが許可したカレンダーを読み書きし、大切な日を常に確認・計算・書き出しでき、自動化から利用できるようにします。

## 基本機能

- 許可されたAppleカレンダーを読み取り、元のアカウント、分類、色を維持。
- 誕生日、記念日、祝日、一度だけの重要日を追跡。
- グレゴリオ暦と中国旧暦の年次ルール、閏月、月末補正に対応。
- システムのローカルカレンダーで「今日」「明日」と残り日数を計算。
- macOSネイティブアプリ、メニューバー表示、WidgetKitデスクトップウィジェット。
- アプリ、メニューバー、ウィジェットはmacOSの言語に合わせ、簡体字中国語、英語、日本語、韓国語、スペイン語、ロシア語で表示。
- 通常の予定、グレゴリオ暦の誕生日、旧暦の誕生日を、明示的に選んだAppleカレンダーへ追加。
- 現在追跡中の重要日をアプリからワンクリックで書き出し。
- Apple SiliconとIntel Macに対応するUniversal Binary（macOS 14以降）。

## AIエージェントに適した設計

`calcount`はエージェントのシェルツールとして直接公開できるローカルCLIです。構造化コマンドはすべて対話メッセージを混ぜずにJSONを出力し、終了コードで引数エラー、カレンダー権限不足、実行時エラーを区別します。

エージェント向けの特長：

- **予測可能な読み取り：** カレンダー一覧、予定検索、直近のカウントダウン、追跡インデックスを取得。
- **安定したJSONエンベロープ：** 成功は `{ "ok": true, "data": ... }`、失敗は `{ "ok": false, "error": { "code": ..., "message": ... } }`。
- **確認可能な書き込み：** 書き込み先のAppleカレンダーを必ず明示し、一括インポートは `--dry-run` で事前確認可能。
- **冪等インポート：** `externalId` により、エージェントが再試行しても重複作成を防止。
- **持ち運べるコンテキスト：** `tracked-events.json` に開始年、暦、月日、繰り返し、次回日、Appleカレンダー参照を保持。
- **ローカルファースト：** サーバーやクラウド上の複製は不要。現在のMacで許可されたEventKitデータだけにアクセス。

よく使う読み取り・書き出しコマンド：

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

エージェントは `jq` でそのまま結果を処理できます：

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

書き込み前に一括インポートを確認：

```bash
./calcount import /path/to/import.json --dry-run
```

`calcount`が現在提供するのはローカルCLI契約です。MCPサーバーやリモートAPIを実装済みとはしていませんが、シェルツール呼び出しに対応する任意のエージェントフレームワークからラップできます。

## 追跡リストJSON

予定内容の信頼できる情報源は常にAppleカレンダーです。`tracked-events.json` は第二のカレンダーデータベースではなく、現在表示される追跡項目のバージョン付き・書き出し可能なインデックスです。

各レコードには次が含まれます：

- 安定したUUID、タイトル、種類（誕生日、記念日、重要日、その他）。
- 開始年、月、日、グレゴリオ暦／旧暦の区分。
- 繰り返し頻度、使用する暦、旧暦の境界処理。
- 次回日、時刻、タイムゾーン、終日フラグ。
- Appleカレンダーのソース、カレンダー、色、再関連付け用ID。
- 追跡モード、追跡開始時刻、固定状態。

完全な匿名例は [tracked-events.example.json](Documentation/tracked-events.example.json) を参照してください。

## インストール

現在のバージョン：**1.0.0**

1. [GitHub ReleasesからCalendarCountdown-1.0.0-macos-universal.dmgをダウンロード](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg)します。
2. CalendarCountdownをApplicationsへドラッグします。
3. アプリを起動し、Appleカレンダーへのフルアクセスを許可します。

1.0.0は現在ad-hoc署名で、Apple Developer ID署名と公証は未実施です。初回起動時はFinderでControlキーを押しながらアプリをクリックし、「開く」を選ぶ必要がある場合があります。

## ソースからビルド

macOS 14以降、Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です。

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## データとプライバシーの境界

- 予定はAppleカレンダーに保存され、本プロジェクト独自のクラウドカレンダーサービスはありません。
- 追跡選択と `tracked-events.json` は表示とユーザー操作による書き出しのためMac内に保存されます。
- 書き込みはユーザーが明示的に選んだAppleカレンダーだけに行われます。
- 実ユーザーの記念日ファイルは `.gitignore` で除外され、公開リポジトリやリリースへ含めません。

## 現在の範囲

- 現在はmacOSをサポート。iPhoneアプリ、iPhoneウィジェット、CloudKitルール同期は今後の対象です。
- CalDAVサーバーではなく、Appleカレンダーのアカウント／分類構造を複製しません。
- 詳細な製品・データ契約は [Documentation/PRODUCT.md](Documentation/PRODUCT.md) を参照してください。

## リポジトリ構成

- `Source/`：Swiftソース、XcodeGen設定、テスト、ビルドスクリプト。
- `Documentation/`：製品契約、インストール説明、匿名JSON例。
- `Releases/1.0.0/`：リリースノートとSHA-256チェックサム。DMGはGitHub Releasesで配布します。

## ライセンス

本プロジェクトは [MIT License](LICENSE) で公開されています。
