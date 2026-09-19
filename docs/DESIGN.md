# koya 設計書

Common Lisp 製ヘッドレス CMS。
2026-09-20 の壁打ちで確定した設計。変更は 14 章の決定ログに追記する。

## 1. コンセプト・ポジショニング

- 個人(単一オーナー)がセルフホストする、小さく堅いヘッドレス CMS。
- ユーザーアカウント管理は持たない。管理画面は単一オーナー向け。
- **マルチテナント対応**: 1インスタンスで複数サイト分のコンテンツを扱う。
  テナントの単位を **space** と呼ぶ(microCMS の「サービス」相当)。
- Strapi / Payload の重さ、microCMS 等 SaaS への依存から離れることが動機。
  既存の skyizwhite/website は microCMS を利用しており、koya への移行先となる。
- 売り: 全部 Lisp(スキーマ・設定・管理 UI)、単一プロセスで動く、
  稼働中に REPL 接続してホットフィックス可能。

## 2. 全体アーキテクチャ

koya は **本体(server)** と **ライブラリ(client)** の2つで構成する。

```
┌─ 利用側プロジェクト(例: website)────────┐      ┌─ koya 本体(Coolify 上)──────────┐
│  (defspace website ...)                  │      │  管理 Web アプリ(hsx + HTMX)     │
│  (defmodel (website blog) ...)  ─ push ─▶│─────▶│  管理 API   /admin/api/...        │
│  (koya:get-list 'blog ...)      ◀ fetch ─│◀─────│  配信 API   /api/v1/{space}/...   │
│  REPL                                    │      │  SQLite(models, contents, ...)   │
└──────────────────────────────────────────┘      └───────────────────────────────────┘
```

- **本体**: 管理 Web アプリ、配信 API、管理 API、SQLite を持つ。デプロイされる唯一のプロセス。
  モデル定義は DB(`models` テーブル)に保存され、管理 UI のフォームはそれから動的に生成される。
- **ライブラリ**(`koya` システム): 利用側プロジェクトが依存する。
  - **config**: `defspace` / `defmodel` でスキーマを Lisp コードとして定義する。
  - **deploy**: 利用側の REPL で `(koya:deploy)` すると、定義が本体の管理 API に送られ、
    本体側のモデル定義が更新される(SQL の DDL は変わらない。4 章参照)。
  - **client**: `get-list` / `get-item` / `get-object` 等で配信 API を叩く。
    microcms-lisp-sdk の後継。モデル定義を知っているので型に応じた変換ができる。
- スキーマの **source of truth は利用側プロジェクトのコード**(git 管理)。本体の DB はその写し。
- 共通部分(フィールド型、バリデーション、スキーマのシリアライズ、ULID)は `koya/core` として
  両者から使う。

### リポジトリ構成

単一リポジトリ、システムは2つ。`koya/core` を共有するため分割しない。
qlot からは git 指定で `koya` だけ引ける。

```
koya/
  koya.asd            ; ライブラリ: koya(client + config)、koya/core
  koya-server.asd     ; 本体: koya-server(koya/core に依存)
  koya-tests.asd      ; rove
  qlfile
  justfile
  Dockerfile
  docs/
    DESIGN.md         ; 本書
    SCHEMA.md         ; スキーマ JSON 仕様
    openapi.yaml      ; 配信 API / 管理 API 仕様
  src/
    core/             ; schema, field-types, validate, serialize, ulid, markdown
    client/           ; http, push, plan, pull, get-list ...
    server/
      app.lisp  main.lisp  document.lisp  helper.lisp
      pages/          ; 管理 UI(ningle-fbr)
      api/            ; 配信 API
      admin-api/      ; 管理 API(schema push/pull/plan、contents CRUD、api-keys、media)
      db/             ; connection, migrations, queries
      lib/            ; env, auth, session, webhook
  tests/              ; src/ を mirror
  assets/style/       ; Tailwind 入力 / 出力
```

## 3. コンテンツモデリング

- **コードファースト**。スキーマは `defmodel` マクロで Lisp コードとして定義し、git 管理する。
- 非エンジニアによる管理 UI でのスキーマ編集はサポートしない(意図的な割り切り)。
- モデル名は `(space model)` の組。microCMS 同様 **list 型 / object 型** を区別する。

```lisp
(defspace website
  :webhooks ("https://skyizwhite.dev/api/revalidate"))

(defmodel (website blog) (:kind :list)
  (title        :text     :required t)
  (description  :text)
  (content      :richtext)
  (tags         :reference (website tag) :many t)
  (published-at :datetime))

(defmodel (website about) (:kind :object)
  (body :richtext))
```

### フィールド型(初期セット)

| 型 | 保存値 | 主なオプション |
|---|---|---|
| `:text` | 文字列 | `:required` `:max-length` `:pattern` `:unique` |
| `:textarea` | 文字列 | 同上 |
| `:richtext` | Markdown 文字列。HTML は保存時に生成し `xxxHtml` として併せて返す | `:required` |
| `:number` | 数値 | `:min` `:max` `:integer` |
| `:boolean` | 真偽 | `:default` |
| `:date` / `:datetime` | ISO 8601 文字列(UTC) | `:required` |
| `:select` | 文字列(`:many` で配列) | `:options ("a" "b")` `:many` |
| `:media` | media id。API では URL 付きオブジェクトに展開 | `:required` |
| `:reference` | content id(`:many` で配列)。`depth` で展開 | `:model` `:many` |
| `:slug` | 文字列。`:from` のフィールドから自動生成 | `:from title` `:unique` |

- リレーション(`:reference`)は同一 space 内のモデルのみ。
- 繰り返し(repeater)、カスタムフィールド(構造体)は初期スコープ外。
- **richtext は Markdown で入力し、API 応答時に HTML へ変換して `xxxHtml` として併せて返す**
  (3bmd、テーブル・コードブロック拡張。コードブロックは `<pre><code class="language-x">` のみでハイライトしない)。
  当初は保存時変換としていたが、DB にレンダラ依存の HTML を残さないため読み出し時変換に変更した。

### deploy(スキーマ反映)

- 転送形式は **JSON**。`defmodel` はマクロとして plist(純粋なデータ)を組み立てるだけで、
  それを JSON 化して管理 API に送る。本体は `models.definition` に JSON のまま保存する。
  本体はリーダー経由の入力を一切受けない。
- **plan → deploy**:
  - `(koya:plan)`: 本体の現在定義と手元の定義の差分(space / model / field の追加・削除・型変更)を表示。
  - `(koya:deploy)`: 差分を表示し、破壊的変更(field 削除・型変更)があれば確認を求める。`:force t` で無条件適用。
  - `(koya:pull)`: 本体側の定義を取得して照合する。
- 差分計算は本体側(`POST /admin/api/schema/plan`)で行い、クライアントは表示するだけ。
- JSON 保存(4 章)のため field 削除でも `contents` のデータは消えない。

## 4. ストレージ

- **SQLite 固定**。抽象化レイヤは設けない。
- ライブラリ: **cl-dbi + dbd-sqlite3 + sxql**。JSON フィルタは sxql の `:raw` で `json_extract` を組む。
  mito は JSON カラム中心の設計と噛み合わないので使わない。
- **汎用 `contents` テーブル + JSON カラム**。モデル毎のテーブルは作らない。

```
schema_version (version PK, applied_at)
spaces         (name PK, webhooks JSON, created_at)
models         (space, name, kind, definition JSON, PK(space, name))
contents       (id ULID PK, space, model, status, published JSON, draft JSON,
                created_at, updated_at, published_at, revised_at)
api_keys       (id ULID PK, space, key_hash, label, created_at)
media          (id ULID PK, space, filename, mime, size, width, height, alt, created_at)
```

- モデル定義の変更はマイグレーション不要(`models.definition` が変わるだけ)。
  バリデーションは `koya/core` が担う。フィールド削除でも `contents` の JSON は残る。
- 絞り込みは SQLite の JSON 関数(`json_extract`)。必要なら後で式インデックスを足す。
- ID は **ULID**。Quicklisp に無いので `koya/core/ulid` として自前実装
  (48bit ミリ秒時刻 + 80bit 乱数、Crockford Base32、乱数は ironclad)。
- 履歴が欲しくなったら `revisions` テーブルを追加する(初期は持たない)。

## 5. API

- **REST のみ**。GraphQL は当面やらない。
- **配信 API**: `GET /api/v1/{space}/{model}`、`GET /api/v1/{space}/{model}/{id}`。
  microCMS 互換のサブセット: `limit` `offset` `orders` `fields` `filters` `depth` `draftKey`。
  レスポンスは `{contents, totalCount, offset, limit}`。object 型は単一オブジェクトを返す。
  `filters` は `[equals]` `[not_equals]` `[contains]` `[exists]` `[not_exists]`
  `[less_than]` `[greater_than]` と `[and]` `[or]` の主要なもののみ。
- **管理 API**: `/admin/api/...`(実装済みのパス)。
  - `GET /admin/api/me`(疎通・認証確認)
  - `GET /admin/api/schema`(pull)、`PUT /admin/api/schema[?force=true]`(push)、`POST /admin/api/schema/plan`
    - push に破壊的変更が含まれ `force` が無い場合は `409 destructive_changes` を返し、`details` に変更一覧を載せる。
      クライアントはそれを表示して確認を取り、`force=true` で再送する(差分計算は本体側)。
  - `/admin/api/contents/{space}/{model}`: `GET`(下書き含む一覧)`POST`(`{"data": {...}, "publish": bool}`)
  - `/admin/api/contents/{space}/{model}/{id}`: `GET` `PATCH`(`{"data"}` を既存データにマージして下書き保存)`DELETE`
  - `/admin/api/contents/{space}/{model}/{id}/publish` `/unpublish` `/draft-key`(`POST`)
  - `/admin/api/keys/{space}`: `GET` `POST`(平文キーは作成時のみ返す)、`/admin/api/keys/{space}/{id}`: `DELETE`
  - `/admin/api/media/{space}`(M2)
- **システムフィールド**: `id` `createdAt` `updatedAt` `publishedAt` `revisedAt` は本体が管理し、
  モデルのフィールド名として予約する(`defmodel` で宣言するとエラー)。microCMS と同じ扱い。
- 配信 API の認証ヘッダは `X-KOYA-API-KEY`。互換のため `X-MICROCMS-API-KEY` も受け付ける
  (microcms-lisp-sdk のベース URL を差し替えるだけで動かすため)。
- 認証は 6 章。

### 非 Lisp クライアントへの配慮

クライアントは将来 Lisp 以外(TypeScript 等)でも実装する。そのため API 関連は Lisp に依存しない形で固める。

- **API は JSON のみ**。キーは camelCase(microCMS 互換。`publishedAt` `totalCount` など)。
  Lisp クライアント側で kebab-case キーワードの plist に変換する(microcms-lisp-sdk と同じ流儀)。
- **スキーマ定義の JSON 形式を仕様として文書化**する(`docs/SCHEMA.md`、`"koyaSchema": 1` のようなバージョン番号付き)。
  `defmodel` はこの JSON を生成する Lisp 用フロントエンドの一つに過ぎない、という位置づけ。
- **管理 API も文書化**し、OpenAPI(YAML)を `docs/openapi.yaml` として置く。
  差分計算などのロジックは本体側に置き、クライアントは薄く保つ。
- エラー形式は統一する: `{"error": {"code": "validation_failed", "message": "...", "details": [...]}}`。
- 日時は ISO 8601(UTC、`Z` 付き)。ID は ULID 文字列。

## 6. 認証・認可

- ユーザーアカウントは持たない。
- 管理画面・管理 API: 単一オーナーシークレット(環境変数 `KOYA_SECRET`)。
  UI はログインフォーム → セッション Cookie、管理 API(push 等)は `Authorization: Bearer`。
  比較は定数時間で行う。
- 配信 API: space ごとの API キー(`X-KOYA-API-KEY`)。**本体側で生成し、管理 UI に表示**する。
  利用側は `.env` に置いてクライアントへ渡す。利用側コードにシークレットを置かない。
  キーは高エントロピーの乱数なので SHA-256 ハッシュで保存する(bcrypt は使わない)。
- ningle-actions のエンドポイントも含め、管理側は全てセッション必須。CSRF は Origin ヘッダ検証。

## 7. 管理 UI

- **Lisp フルスタック**。フロントも含めて Lisp で書く。
- SSR: hsx(HTML S 式)+ HTMX で部分更新。SPA・JS ビルドチェーンは持ち込まない。
- ルーティング: ningle-fbr(ファイルベース)、部分更新エンドポイント: ningle-actions。
- CSS: Tailwind CSS v4(スタンドアロンバイナリ、`justfile` でビルド)。
- フォームは DB 上のモデル定義から動的生成(フィールド型 → 入力コンポーネントの対応表)。
- richtext は Markdown のテキストエリア + プレビュー(HTMX でサーバ側変換)。
- 画面(実装済みパス): `/login`、`/`(space 一覧)、`/s/{space}`(モデル一覧)、`/s/{space}/keys`(API キー)、
  `/s/{space}/m/{model}`(コンテンツ一覧。object 型は単一コンテンツの編集画面へリダイレクト)、
  `/s/{space}/m/{model}/{id}`(編集。`{id}` = `new` で新規)。**メディアライブラリ**(8 章)は M2。
- フォームは通常の POST(`action` = save / publish / unpublish / delete / draft-key)で送り、
  HTMX は Markdown プレビュー(ningle-actions の `preview-markdown`)に使う。
- 管理側の POST は `Origin` / `Referer` が `Host` または `KOYA_BASE_URL` と一致することを要求する(CSRF 対策)。
- `:datetime` の入力は `datetime-local` で、値は UTC として扱う(タイムゾーン変換は M2 で JS を足す)。
- `:slug` はフォーム・API のどちらでも、空なら `:from` のフィールドから本体側で自動生成する(ASCII のみ)。
- `:reference` / `:media` の入力は M1 では id のテキスト入力。ピッカーは M2。
- `:media` フィールドはメディアライブラリをモーダルで開き、その場でアップロードと選択を行う(8 章)。
- 実装スタイルは skyizwhite/website に準拠(10 章)。

## 8. メディア・アセット

- 初期スコープは **画像アップロードのみ**。
- **メディアライブラリ方式**: メディアは常に space ごとのライブラリに属し、コンテンツのフィールドは
  ライブラリ内のメディアを参照する。フィールドにファイルを直接紐付ける方式は取らない。
  Contentful / WordPress のメディアライブラリと同じ流儀。
- ライブラリには2つの入口がある。どちらも同じ一覧・アップロードのコンポーネントを使う。
  - **専用のメディア管理画面**(space ごと): アップロード、一覧、詳細、削除。
  - **コンテンツ編集画面の `:media` フィールド**: 「メディアを選ぶ」でメディアライブラリを
    **モーダル(HTMX)で開き、その場でアップロードも選択も行える**。アップロードしたものは
    そのままライブラリに登録され、選択するとフィールドに id がセットされる。
  - 一覧はページング・ファイル名検索つき。
- メディア管理画面の機能: アップロード(複数可)、一覧(サムネイル、ファイル名、サイズ、寸法、登録日)、
  詳細(URL コピー、alt テキスト編集)、削除(コンテンツから参照中なら警告)。
- 本体のローカルディスク(Docker ボリューム)に保存し、`/media/{space}/{id}.{ext}` で配信する。
- リサイズ・変換・外部ストレージ(S3 等)は持たない。必要になったら CDN 側(Cloudflare Images 等)か後続フェーズで。
- フィールド型 `:media` は media の id を参照し、API では `{url, width, height, alt}` のオブジェクトに展開する。
- 管理 API: `GET/POST /admin/api/{space}/media`、`GET/PATCH/DELETE /admin/api/{space}/media/{id}`。

## 9. 下書き・公開・バージョニング

- `contents.published` と `contents.draft` の2カラム。status は `draft` / `published` / `published+draft`。
- `draftKey` でドラフトをプレビュー取得(microCMS 互換)。
- 公開・更新・削除時に space の webhook を呼ぶ(website の revalidate が受け口)。
  ペイロードは microCMS 互換に近い形(`api`、`id`、`type`、`contents.old/new`)。
- 履歴(revisions)は初期スコープ外。

## 10. 技術スタック

website(skyizwhite/website)で実績のある構成をそのまま踏襲する。

| 層 | 選定 |
|---|---|
| 実装 | SBCL、**package-inferred-system**(`src/` 配下のファイル = パッケージ) |
| 依存管理 | qlot(`qlfile`、自作ライブラリは git 指定) |
| HTTP | Clack / Lack。開発: Hunchentoot、本番: Woo |
| ルータ | jingle(ningle 拡張)+ ningle-fbr |
| 部分更新 | ningle-actions + HTMX |
| テンプレート | hsx |
| ミドルウェア | lack-mw(trailing-slash)、clack-errors、lack accesslog / mount / session |
| DB | cl-dbi + dbd-sqlite3 + sxql |
| JSON | jzon(com.inuoe.jzon)+ kebab(キー変換) |
| HTTP クライアント(client) | dexador |
| Markdown | 3bmd(+ tables / code-blocks 拡張、独自プレーンレンダラ) |
| 暗号・乱数 | ironclad |
| 日時 | local-time |
| 環境変数 | cl-dotenv(`.env`) |
| CSS | Tailwind CSS v4 standalone |
| テスト | **fukamachi/rove**(`koya-tests` システム、`tests/` が `src/` を mirror) |
| タスク | justfile |
| 配布 | Docker(`fukamachi/qlot` ベース)→ Coolify |

website から流用するパターン:

- `*page-app*` / `*api-app*` / `*admin-api-app*` / `*actions-app*` を分け、
  `jingle:process-response :around` でレスポンス型(HTML / JSON)を app 単位で決める。
  `/api` `/admin/api` は lack mount で合成。
- `~document` コンポーネントでページ骨格を共通化。
- `src/server/lib/env.lisp` の `env-var` マクロで環境変数を関数化。
- `main.lisp` に `start` / `stop` / `reload` を置き、REPL 駐在で開発。
- `:around` 等 CLOS ベースで拡張点を作る。

### テスト方針

- rove。`tests/` は `src/` を mirror し、`koya-tests.asd` の `test-op` で一括実行。
- `koya/core`(バリデーション、スキーマ差分、ULID、Markdown)はユニットテストを厚く。
- 本体はインメモリ SQLite(`:memory:`)でリポジトリ層と API をテスト。
- クライアントは本体をテスト内で起動して結合テスト(push → get-list の往復)。

## 11. 拡張性(Lisp らしさ)

- スキーマ、設定はすべて Lisp(利用側プロジェクト)で書き、`koya:deploy` で反映。
- **ロジック(保存前後フック等)は本体に置かず、webhook で利用側に任せる**。本体は汎用で、
  利用側の Lisp コードを実行しない。
- 本体が持つのは宣言的な制約のみ(required、文字数上限、正規表現、一意制約、slug 自動生成など
  `defmodel` のフィールドオプション)。
- 稼働中の本体に Slynk/Swank で接続できる(ポートはローカル/内部ネットワーク限定)。
- 本体自身を Lisp プロジェクトとして拡張する余地(`:around` 等)は残すが初期スコープ外。

## 12. デプロイ・運用

- Docker イメージ 1 つ + SQLite ファイルとメディア(ボリューム)で完結。Coolify で運用。
- 本体テーブルのマイグレーションは **起動時に自動適用**。`schema_version` テーブルと
  番号付き Lisp 関数のリストで up のみ持つ。down は持たない。
- バックアップは Coolify のボリュームバックアップに任せる。
  `POST /admin/api/backup`(`VACUUM INTO`)は後続フェーズ。
- 環境変数: `KOYA_SECRET`、`KOYA_DB_PATH`、`KOYA_MEDIA_DIR`、`KOYA_BASE_URL`、`KOYA_ENV`。
- `GET /health`(認証なし、DB 疎通を含む)をヘルスチェックに使う。

## 13. マイルストーン

### M1: website が microCMS から乗り換えられる最小構成

- `koya/core`: schema plist、フィールド型(text / textarea / richtext / datetime / boolean)、
  バリデーション、JSON シリアライズ、ULID、Markdown 変換。
- 本体: マイグレーション、schema push/pull/plan、contents CRUD、公開/下書き、`draftKey`、
  配信 API(`limit` `offset` `orders` `fields` `filters[equals]`)、API キー、webhook、
  管理 UI(ログイン、一覧、編集、公開)。
- client: `defspace` `defmodel` `plan` `push` `pull` `get-list` `get-item` `get-object`。
- 完了条件: website の `lib/cms.lisp` を koya client に差し替え、blog / about / works が動く。

### M2: 残りのフィールド型とメディア

- `:number` `:date` `:select` `:reference`(`depth`)`:slug` `:media`、画像アップロード、
  `filters` の残りの演算子、`docs/SCHEMA.md` と `docs/openapi.yaml` の整備。

### M3: 運用・拡張

- revisions、`backup`、Slynk 接続手順、非 Lisp クライアント(TypeScript)の着手。

## 14. 決定ログ

| 日付 | 決定 | 理由 |
|---|---|---|
| 2026-09-20 | 個人用・アカウント無し・space によるマルチテナント | オーナーは1人だが複数サイトを持つ |
| 2026-09-20 | スキーマは `defmodel` によるコードファースト | Lisp を選ぶ意味を出す。git 管理可 |
| 2026-09-20 | SQLite 固定 | 小屋。運用コスト最小 |
| 2026-09-20 | REST のみ、配信/管理 API 分離 | GraphQL は需要が出てから |
| 2026-09-20 | 管理 UI は hsx + ningle-fbr + ningle-actions + HTMX + Tailwind | website と同じ Lisp フルスタック |
| 2026-09-20 | package-inferred-system | website 同様、ningle-fbr の前提でもある |
| 2026-09-20 | 本体(server)+ ライブラリ(client/config)の2構成、REPL から `koya:deploy` | スキーマは利用側コードが正、本体は汎用 |
| 2026-09-20 | 反映関数の名前は `deploy`(`push` は `cl:push` と衝突するため) | shadow してまで `push` を使わない |
| 2026-09-20 | `(space model)` の組でモデル命名、list/object 型を区別 | website の about/works が object 型 |
| 2026-09-20 | 汎用 contents テーブル + JSON、ULID | モデル変更でマイグレーション不要 |
| 2026-09-20 | 配信 API は microCMS 互換サブセット | website がほぼ無改修で移行できる |
| 2026-09-20 | richtext は Markdown 入力 → HTML 変換 | JS エディタを持ち込まない |
| 2026-09-20 | push は JSON 転送、plan → apply、差分計算は本体側 | 非 Lisp クライアントを将来実装するため |
| 2026-09-20 | API は camelCase JSON、スキーマ JSON と OpenAPI を仕様化 | 同上 |
| 2026-09-20 | フックは webhook で利用側へ。本体は宣言的制約のみ | 本体を汎用に保つ |
| 2026-09-20 | 配信 API キーは本体で生成・管理、SHA-256 保存 | 利用側コードにシークレットを置かない |
| 2026-09-20 | メディアは画像のみ・ローカルディスク・変換なし | 小屋 |
| 2026-09-20 | メディアはライブラリ方式。専用画面と、編集画面から開くモーダルの2入口でアップロード・選択 | 同じ画像の再利用、管理の一元化 |
| 2026-09-20 | 単一リポジトリ、`koya` / `koya-server` の2システム | `koya/core` を共有 |
| 2026-09-20 | cl-dbi + dbd-sqlite3 + sxql、ULID 自前実装 | mito は JSON 中心設計と合わない。ULID は Quicklisp に無い |
| 2026-09-20 | Markdown は 3bmd | 保守状況と拡張の充実 |
| 2026-09-20 | 本体テーブルは起動時自動マイグレーション(up のみ) | 単一プロセス運用で十分 |
| 2026-09-20 | テストは fukamachi/rove | website と同じ |
| 2026-09-20 | JSON は jzon + kebab(jonathan ではなく) | microcms-lisp-sdk と同じ流儀。hash-table ベースで扱いやすい |
| 2026-09-20 | richtext の HTML 化は読み出し時 | DB にレンダラ依存の HTML を残さない |
| 2026-09-20 | システムフィールド名(publishedAt 等)を予約 | microCMS 同様、公開日時は本体が管理する |
| 2026-09-20 | 破壊的 push は 409 → `force=true` で再送 | 確認の UI をクライアント側に置きつつ判定は本体 |
| 2026-09-20 | 管理 API は `/admin/api/contents/…` `/admin/api/keys/…` に配置 | `schema` 等の固定パスと space 名の衝突を避ける |
| 2026-09-20 | 配信 API は `X-MICROCMS-API-KEY` も受理 | 既存 SDK からの移行を容易にする |
