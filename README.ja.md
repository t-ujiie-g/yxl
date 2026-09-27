# yxl

[English](./README.md) | **日本語**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

**Excel ブックを、バージョン管理できる YAML で管理する。** `yxl` は
[MoonBit](https://www.moonbitlang.com/) 製のコマンドライン**コンパイラ**です。
宣言的な `*.yxl.yaml` スペックを書くと、`yxl build` がそれを Excel 互換の本物の
`.xlsx` に変換します。

スプレッドシートをコードとして扱い、コードと同じ性質を持たせます。

- **差分が取れ、レビューできる** — ブックが Git 管理下のテキストになります。
- **DRY / 単一の情報源** — 値・数式・スタイルを**一度**書いて何度も参照すれば、
  管理する場所は一か所です。しかも Excel の*ネイティブ*な共有機構（共有文字列、
  名前の定義、共有数式、単一のスタイル ID）にコンパイルされます。一か所を直せば
  全部が変わります。
- **柔軟な構成** — データと書式を `$include` で複数ファイルに分けることも、
  CSV や JSON の表から範囲を直接流し込むことも、すべてを 1 ファイルに書くことも
  できます。結果はどれも同じです。
- **1 つのスペックから複数のブック** — `params:` を宣言し、ビルドごとに
  `--set region=EMEA` で上書きします。
- **ネイティブコマンド 1 つ** — 最初のスペックは `yxl init`、あとは
  `yxl build report.yxl.yaml -o report.xlsx`。

`.xlsx` のバイト列は、成熟したライブラリ
[`moonbitlang/mbtexcel`](https://mooncakes.io/docs/moonbitlang/mbtexcel)（Go の
excelize の MoonBit 移植）が生成します。`yxl` はその上に乗る言語、再利用・重複排除
エンジン、バリデータ、そして CLI です。スプレッドシート*ライブラリ*をもう一つ
作ったのではなく、コードを書くより YAML を編集したい人のための宣言的な作成手段です。

> ⚠️ **ステータス: プレリリース、スキーマは未凍結。** `yxl build` は現時点で
> 動作します — 値、数式、日付、期間、リッチテキスト、スタイル、レイアウト、
> 印刷設定、複数ファイルのスペック、外部 CSV/JSON データ、パラメータ、個別の
> 上書き、入力規則、条件付き書式、ハイパーリンク、メモ、保護、Excel テーブル、
> グラフ、画像、図形、シートの背景、スパークライン、フォームコントロール、
> テーブルのスライサー、ピボットテーブルがすべてコンパイルでき、CLI には `init`、
> `--check`、`--set`、安定した終了コードがあります。今後の予定はパフォーマンス
> 改善、インポート、スキーマの凍結です — **v1.0 まではスキーマが変わる可能性が
> あります。** フェーズ計画と変更履歴は [`ROADMAP.md`](./ROADMAP.md) を参照して
> ください。

## お試し

```yaml
# report.yxl.yaml
params:                      # ビルドごとに --set で上書きできる
  region: APAC
  quarter: Q3

defs:                        # 一度宣言し、名前で参照する
  styles:
    base:   { font: { name: Calibri, size: 11 } }
    title:  { extends: base, font: { bold: true, size: 16 } }
    header: { extends: base, font: { bold: true, color: "FFFFFF" }, fill: "1F3864" }
    total:  { extends: base, font: { bold: true } }

sheets:
  - name: "${region}"
    freeze: A4               # データをスクロールしても見出し行は固定
    merges: [A1:B1]
    columns:
      - at: A
        width: 18
      - at: B
        width: 14
        format: "#,##0"      # 列全体の既定の表示形式
    cells:
      A1: { value: "${quarter} ${region} sales", style: title }
      A3: { value: Region, style: header }
      B3: { value: Revenue, style: header }
      A7: { value: Total, style: total }
      B7: { formula: "SUM(B4:B6)", style: total }
    data:
      - at: A4
        csv: data/sales.csv  # スペックに書き写さず、ファイルから行を読む —
                             # `values:` でここに直接書いてもよい
    print:
      area: A1:B7
      orientation: landscape
      fit: { width: 1 }      # 横 1 ページに収める
```

```bash
yxl build report.yxl.yaml -o q3-apac.xlsx
yxl build report.yxl.yaml -o q4-emea.xlsx --set region=EMEA --set quarter=Q4
```

宣言したスタイルは、何個のセルに使っても**単一の** Excel スタイル ID に
コンパイルされます。`defs.values` の各エントリは**名前の定義**になるので、Excel
上で編集するとすべての参照先に反映されます。未知のキー、不正なセル参照、参照先の
ない `$ref`、インクルード・スタイル・パラメータ間の循環はビルドを失敗させ、
ファイル名を示す診断を出します。値が黙って捨てられることはありません。

## インストール

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.ps1 | iex
```

どちらもお使いのプラットフォーム向けの
[最新リリース](https://github.com/t-ujiie-g/yxl/releases)を取得し、
**SHA-256 を検証して** `yxl` をインストールします。インストール先は
`~/.local/bin`（Windows では `%LOCALAPPDATA%\yxl\bin`）です。バージョンの固定や
インストール先の指定は `YXL_VERSION` と `YXL_INSTALL_DIR` で行います。

```bash
YXL_VERSION=0.1.0 YXL_INSTALL_DIR=/usr/local/bin \
  curl -fsSL https://raw.githubusercontent.com/t-ujiie-g/yxl/main/install.sh | sh
```

ビルド済みバイナリは **Linux x86_64** と **macOS arm64**（Apple シリコン）向けです。
Intel Mac やその他のプラットフォームでは、下記の手順でソースからビルドしてください。
スクリプトをシェルにパイプするのは慎重に行うべきことです — 気になる場合は先に
[`install.sh` を読む](./install.sh)か、リリースのアセットから手動で入れるか、
ソースからビルドしてください。

### ソースから

[MoonBit](https://www.moonbitlang.com/download) をインストールした状態で:

```bash
git clone https://github.com/t-ujiie-g/yxl.git
cd yxl
moon build --target native --release
install -m 755 _build/native/release/build/cmd/main/main.exe ~/.local/bin/yxl
```

macOS はダウンロードしたバイナリに隔離属性を付けます。Gatekeeper に止められたら
`xattr -d com.apple.quarantine ~/.local/bin/yxl` で解除してください。

パスの区切り文字はどちらでも構わないので、Windows で
`yxl build specs\report.yaml` と書けますし、スペック内の
`$include: data/x.yaml` も移植性を保ちます。

**Windows の制限が 1 つあります:** 現在、*コマンドライン*に非 ASCII 文字を
渡せません — `yxl build 売上\report.yaml` は失敗します。ランタイムは引数を UTF-8
として読みますが、Windows はシステムのコードページで渡してくるためです
（[upstream](https://github.com/moonbitlang/x): "TODO: Handle other encodings"）。
スペック*内部*のパスは影響を受けません — `$include: 表/theme.yaml` や
`csv: 売上/data.csv` は動きます。これらは UTF-8 のファイルから読まれるからです。
コマンドラインで渡すスペックのファイル名だけ ASCII にしておけば、そこから参照する
ものはどんな文字でも構いません。

## 使い方

```bash
yxl init -o sheet.yxl.yaml                   # 最初のスペック: 空のシートが 1 枚
yxl build report.yxl.yaml -o report.xlsx     # コンパイル
yxl build report.yxl.yaml --check            # 検証のみ、何も書き出さない
yxl build report.yxl.yaml -o r.xlsx --set region=EMEA
yxl extract legacy.xlsx -o legacy.yxl.yaml   # 既存のブック → たたき台のスペック
yxl version                                  # バージョンを表示
yxl help                                     # 使い方の全体
```

`init` は書き始めるための場所を用意します — 空のシート 1 枚だけで、先に消す必要の
ある作例ではありません。生成ファイルに入るビルドコマンドには指定したファイル名が
入り、既存のスペックは `--force` を付けない限り上書きしません。

スキーマの全体は [`docs/spec.md`](./docs/spec.md)（英語）にあります。`extract` は
一方向の移行補助で往復変換ではなく、その §22 で説明しています。

**エディタでは**、このページから生成した JSON Schema により、すべてのキーの補完、
ホバー時のリファレンスの説明文、存在しないキーへの波線が使えます。VS Code では
YAML 拡張機能を一度インストールします。

```bash
code --install-extension redhat.vscode-yaml
```

そのうえで、スペックの 1 行目でスキーマを指定するか —

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/t-ujiie-g/yxl/main/docs/yxl.schema.json
```

— プロジェクト内のすべてのスペックに対して `.vscode/settings.json` で一度だけ
指定します（なければ作成してください。同じブロックはユーザー設定でも使えます。
JetBrains IDE では *Languages & Frameworks → Schemas* に同等の設定があります）。

```json
{
  "yaml.schemas": {
    "https://raw.githubusercontent.com/t-ujiie-g/yxl/main/docs/yxl.schema.json": "*.yxl.yaml"
  }
}
```

`*.yxl.yaml` という命名を守る価値があるのはこの glob のためです。`$include` で
取り込まれるファイルはスペックそのものではなくその*一部*なので、マッチしては
いけません — マッチすると `sheets` のない文書として報告されてしまいます。ほかに
設定は不要です。モードラインは `yaml-language-server` 自身のものなので、Neovim や
Helix も VS Code と同じように読みます。ローカルのチェックアウトを指す方法や、
スキーマがあえて `yxl build` に任せている点は
[§24](./docs/spec.md#24-editor-support) で扱っています。

終了コードはリリースをまたいで安定しています。

| コード | 意味 |
|---|---|
| `0` | 成功 |
| `1` | スペックが不正、またはファイルの読み書きに失敗 |
| `2` | コマンドラインそのものが誤り |

## 作例

[`examples/`](./examples) は実例集で、CI がすべてのファイルをコンパイルするため、
内容がコンパイラとずれることはありません。

| 作例 | 内容 |
|---|---|
| [`quickstart.yxl.yaml`](./examples/quickstart.yxl.yaml) | セルの種類、表示形式、数式、列に展開される数式、インラインで書いた行のまとまり |
| [`styling.yxl.yaml`](./examples/styling.yxl.yaml) | 一度だけ宣言するスタイル、`extends`、名前の定義、リッチテキスト、条件付き書式 |
| [`layout.yxl.yaml`](./examples/layout.yxl.yaml) | セル結合、見出しの固定、行・列のサイズ指定とグループ化、シートの表示状態、印刷設定、文書プロパティ、画像、透かしの背景 |
| [`modular.yxl.yaml`](./examples/modular.yxl.yaml) | `$include`、CSV / JSON の `data:`、それで埋まる範囲に置いた Excel テーブル、それを絞り込むスライサー |
| [`parameters.yxl.yaml`](./examples/parameters.yxl.yaml) | `${}` と `--set` を使った `params:` |
| [`interactive.yxl.yaml`](./examples/interactive.yxl.yaml) | ドロップダウンなどの入力規則、オートフィルター、ハイパーリンク、メモ、シートの保護、チェックボックスとスピンボタン |
| [`charts.yxl.yaml`](./examples/charts.yxl.yaml) | 縦棒・円・横棒グラフ、セルから名前を取る系列、別シートを描くグラフ |
| [`pivots.yxl.yaml`](./examples/pivots.yxl.yaml) | 2 つのピボットテーブル: 行、列、`filters:` 軸、2 種類の集計 |
| [`shapes.yxl.yaml`](./examples/shapes.yxl.yaml) | 雲形のスタンプ、2 行のテキストを持つ山形矢印、固定配置の星 |
| [`sparklines.yxl.yaml`](./examples/sparklines.yxl.yaml) | 行ごとのマーカー付き折れ線と、別シートを描く勝敗セル |
| [`overrides.yxl.yaml`](./examples/overrides.yxl.yaml) | 例外を例外として書く個別の上書き: 列に展開される数式に従わない行、修正した値、スタイルだけの変更 — それぞれに理由付き |
| [`columns.yxl.yaml`](./examples/columns.yxl.yaml) | 列を文字ではなく名前で扱う前年比レポート: 項目ごとに配置する `defs.blocks` グループを持つ `layouts:`、2 行の結合見出し、合計行、`{{name}}` 数式、列ごとの条件付き書式、入力列だけを埋める行 |
| [`subtotals.yxl.yaml`](./examples/subtotals.yxl.yaml) | 店舗一覧とその下の小計 — 支店別、支店内のチャネル別、総計 — を固定順の生きた `SUMIFS` 数式で。別シートが名前で合計する名前付きレイアウト、一覧の下に置き名前で描くグラフ、それを元にした店舗ドロップダウン、データの値で行を見つける上書き |
| [`workbook.yxl.yaml`](./examples/workbook.yxl.yaml) | 実際のブックを保つためのレイアウト: 1 シート 1 ファイル、一度だけ名付けたスタイル、すべてのシートが参照する 1 つの店舗マスタ、`--set` で差し替える月次データ |

```bash
yxl build examples/quickstart.yxl.yaml -o quickstart.xlsx
```

## AI スキル

[`skills/`](./skills) には Agent Skills — AI コーディングエージェント（Claude Code、
Codex、Cursor、OpenCode など）が従えるワークフローのチェックリスト — があります。

| スキル | 対象 |
|---|---|
| [`yxl-authoring`](./skills/yxl-authoring/SKILL.md) | 全般的なワークフロー: 指示がなければ組む既定の構成（1 シート 1 ファイル、一度だけ名付けたスタイル、共有リストごとに 1 つのマスタ）、ゼロからのスペック作成、既存スペックの編集、月次の運用 |
| [`extract-to-spec`](./skills/extract-to-spec/SKILL.md) | 移行: `yxl extract` で既存ブックからたたき台を作り、それを保守しやすく書き直す手順 |

```bash
npx skills add t-ujiie-g/yxl        # どのエージェントでも — skills/ からインストール
```

Claude Code では、このリポジトリをプラグインのマーケットプレイスとして追加し
（`/plugin` → Add Marketplace → `t-ujiie-g/yxl`）、`yxl-skills` をインストール
することもできます。

## 仕組み

```
report.yxl.yaml
   → parse（YAML → 文書ツリー）
   → load + validate + 参照の解決（型付きモデル、ファイル名を示す診断）
   → emit: 共有スタイル・文字列・名前の定義をインターン   ← DRY エンジン
     差し替え可能なバックエンド（moonbitlang/mbtexcel）経由
   → report.xlsx
```

パイプラインの中核はファイルシステムに触れず、文字列とバイト列の上で単体テスト
できます。ディスクに触れるのは CLI だけです。Excel バックエンドは差し替えられる
よう境界の向こうに置いています（[`ROADMAP.md §7`](./ROADMAP.md) の ADR-002 を
参照）。

## パッケージ

| パッケージ | 役割 |
|---|---|
| `diag` | 診断と、ソース位置付きのサブドメインエラー |
| `units` | 型安全なセル参照、色、日付 |
| `yaml` | YAML ソース → 文書ツリー |
| `model` | 型付き中間表現 |
| `loader` | 文書ツリー → モデル: スキーマ検証、参照の解決 |
| `emit` | モデル → `.xlsx` バイト列（mbtexcel ベース）、スタイル・文字列のインターン |
| `read` | `.xlsx` バイト列 → モデル。`emit` の逆（`yxl extract` 用） |
| `render` | モデル → 文書ツリー。`loader` の逆で、抽出したスタイルに名前を付ける |
| `cli`（`cmd/main`） | 引数の解析、ファイル I/O、終了コード |
| `examples` | テスト専用: `examples/` の作例をコンパイルして検証する |

## 開発

```bash
moon check --deny-warn      # 型チェック
moon test                   # テスト
moon fmt                    # 整形
moon info                   # .mbti インターフェイスファイルの再生成
moon build --target native  # CLI のビルド
```

`main` は保護されています。変更はプルリクエストで取り込み、CI が通っている必要が
あります。コミットに `vX.Y.Z` のタグを付けるとバイナリがビルドされリリースが
公開されます — タグ、`moon.mod`、`yxl version` が表示するバージョンが一致しないと、
リリースジョブはビルド前に止まります。

方針、フェーズの範囲、設計判断（ADR）、変更履歴はすべて単一の情報源である
[`ROADMAP.md`](./ROADMAP.md) にあります。コントリビュータと AI エージェント向けの
約束事は [`AGENTS.md`](./AGENTS.md)（`CLAUDE.md` はそのシンボリックリンク）、
スペックの形式は [`docs/spec.md`](./docs/spec.md) にあります（いずれも英語）。

## ライセンス

Apache-2.0。[`LICENSE`](./LICENSE) を参照してください。
