# Redmine Versioned File CF Plugin

このプラグインは `ファイル（リビジョン管理）` という新しいカスタムフィールド形式を追加し、アップロードされたテキストファイルの履歴管理を可能にします。

英語版: [README.md](README.md)

## 機能

- `ファイル（リビジョン管理）` をカスタムフィールド形式として追加
- 既存のファイルカスタムフィールドと同様にファイルのアップロードに対応
- 登録されたファイルの履歴表示
- 登録されたファイルの差分表示

### 注意

- アップロード対象はテキストファイルを前提としています
- 差分ファイルのダウンロードにはサーバー上に Git が必要です

## インストール

### 1. ダウンロード
#### Git を使用する場合
```shell
cd your_redmine/plugins
git clone https://github.com/sk-ys/redmine_versioned_file_cf.git
```
#### Git を使用しない場合
1. 以下のリンクからダウンロードしてください
   - リリース版: https://github.com/sk-ys/redmine_versioned_file_cf/releases
   - 最新版: https://github.com/sk-ys/redmine_versioned_file_cf/archive/refs/heads/main.zip
2. plugins フォルダに `redmine_versioned_file_cf` というフォルダ名で展開してください

### 2. マイグレーション
Redmine のルートディレクトリで以下を実行してください。

```shell
bundle exec rake redmine:plugins:migrate NAME=redmine_versioned_file_cf RAILS_ENV=production
```

### 3. Redmine を再起動
Redmine を再起動してください。

## 使い方

1. 管理画面で custom field を新規作成します（Issue・Project・Version など任意のオブジェクトを選択）。
2. フォーマットに `ファイル（リビジョン管理）` を選びます。
3. 必要なら許可拡張子を設定します。
4. 各オブジェクトの編集画面からテキストファイルをアップロードします。
5. 詳細画面の下部に履歴一覧と差分リンクが表示されます。

### 既存カスタムフィールドの UI からの変換

custom field の編集画面では、`ファイル` 形式と `ファイル（リビジョン管理）` 形式のときだけ、専用の変換ボタンが表示されます。

- `ファイル` -> `ファイル（リビジョン管理）`: 既存のファイルカスタムフィールドをリビジョン管理形式へ変換します。
- `ファイル（リビジョン管理）` -> `ファイル`: 通常のファイル形式へ戻します。

`ファイル（リビジョン管理）` から `ファイル` へ変換する場合、`vfcf_file_revisions` に保存されている履歴はすべて削除されます。現在のファイルは通常のファイルカスタムフィールドの添付として保持されます。

## テスト

Redmine のルートディレクトリで test DB を準備します。

```shell
bundle exec rails db:test:prepare RAILS_ENV=test
bundle exec rake redmine:plugins:migrate NAME=redmine_versioned_file_cf RAILS_ENV=test
```

続いてプラグインのテストを実行します。

```shell
bundle exec rails test plugins/redmine_versioned_file_cf/test RAILS_ENV=test
```

補足:

- もし minitest / SimpleCov 読み込み不具合が発生する場合は、`MT_NO_PLUGINS=1` をコマンドの先頭に付与してください。

## メンテナンス

必要に応じて、コンテナレコードが既に削除された孤立した添付ファイルを以下のコマンドで削除できます。

Redmine ルートで以下を実行します。

```shell
bundle exec rake versioned_file_cf:cleanup_orphan_attachments RAILS_ENV=production
```

既存のファイルカスタムフィールドを Versioned file に置き換えることもできます。

Redmine ルートで以下を実行します。

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 RAILS_ENV=production
```

データを変更せず移行可否だけ確認する場合は以下を実行します。

```shell
bundle exec rake versioned_file_cf:migrate_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

既存の Versioned file カスタムフィールドを File に戻すこともできます。このとき現在のファイルは保持し、`vfcf_file_revisions` の履歴は削除します。

Redmine ルートで以下を実行します。

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 RAILS_ENV=production
```

データを変更せず変換可否だけ確認する場合は以下を実行します。

```shell
bundle exec rake versioned_file_cf:revert_file_custom_field ID=12 DRY_RUN=1 RAILS_ENV=production
```

動作:

- 孤立レコードが 0 件の場合はメッセージを表示して終了します。
- 孤立レコードがある場合は削除を実行し、削除した Attachment ID を表示します。
- 移行 task の対象は、既存のファイルカスタムフィールド形式の custom field のみです。
- 添付済みの値にテキスト以外のファイルや不整合な Attachment が含まれる場合は、変更を加えずに移行を中止します。
- 復元 task の対象は、Versioned file 形式の custom field のみです。
- 復元 task は current のファイルを通常の file custom field の添付へ戻し、履歴レコードをすべて削除します。
