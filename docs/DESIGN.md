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
│  (defmodel (website blog) ...)  ─ deploy ▶│─────▶│  管理 API   /admin/api/...        │
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
    SCHEMA.md         ; スキーマ JSON 仕様(未作成、M2)
    openapi.yaml      ; 配信 API / 管理 API 仕様(未作成、M2)
  src/
    main.lisp         ; koya パッケージ(config + client の再エクスポート)
    config.lisp       ; defspace / defmodel / current-schema
    client.lisp       ; HTTP クライアント: plan / deploy / pull、get-list ...、管理 API ラッパ
    core/             ; schema, validate, diff, json, case, time, ulid
    server/
      app.lisp  main.lisp  document.lisp
      pages/          ; 管理 UI(ningle-fbr。ディレクトリ = URL)
      components/     ; フォーム入力などの hsx コンポーネント
      api/            ; 配信 API
      admin-api/      ; 管理 API(schema plan/deploy/pull、contents CRUD、keys)
      db/             ; connection, migrations, schema-store, contents, api-keys
      lib/            ; env, auth, http, query, presenter, content-service, forms, page, webhook
  tests/              ; src/ を mirror
  assets/             ; style/(Tailwind 入力 / 出力)、js/(htmx, quill, koya-editor.js)
```

## 3. コンテンツモデリング

- **コードファースト**。スキーマは `defmodel` マクロで Lisp コードとして定義し、git 管理する。
- 非エンジニアによる管理 UI でのスキーマ編集はサポートしない(意図的な割り切り)。
- モデル名は `(space model)` の組。microCMS 同様 **list 型 / object 型** を区別する。

```lisp
(defspace website
  ;; 評価される。全モデルに適用。URL 文字列だけでも可(label = URL、既定イベント)
  :webhooks (list (webhook "revalidate" "https://skyizwhite.dev/api/revalidate")))

(defmodel (website blog) (:kind :list
                          ;; このモデルだけに追加される webhook
                          :webhooks (list (webhook "preview-build" "https://preview.example/hook" :events '(:draft))))
  (title        :text     :required t)
  (description  :text)
  (content      :richtext)
  (tags         :reference :model tag :many t)
  (published-at :datetime))

(defmodel (website about) (:kind :object)
  (body :richtext))
```

### フィールド型(初期セット)

| 型 | 保存値 | 主なオプション |
|---|---|---|
| `:text` | 文字列 | `:required` `:max-length` `:pattern` `:unique` |
| `:textarea` | 文字列 | `:required` `:max-length` |
| `:richtext` | HTML 文字列(Quill で編集、API はそのまま返す) | `:required` |
| `:number` | 数値 | `:required` `:min` `:max` `:integer` |
| `:boolean` | 真偽 | `:required` `:default` |
| `:date` / `:datetime` | ISO 8601 文字列(UTC) | `:required` |
| `:select` | 文字列(`:many` で配列) | `:options ("a" "b")` `:many` |
| `:media` | media id。API では URL 付きオブジェクトに展開 | `:required` |
| `:reference` | content id(`:many` で配列)。`include` で展開 | `:model` `:many` |
| `:slug` | 文字列。`:from` のフィールドから自動生成 | `:from title` `:unique` |

- リレーション(`:reference`)は同一 space 内のモデルのみ。
- 繰り返し(repeater)、カスタムフィールド(構造体)は初期スコープ外。
- **richtext は HTML 文字列**。管理 UI では Quill(`assets/js/quill`、Snow テーマ)で編集し、
  `getSemanticHTML()` の結果を隠しフィールド経由で送る。API はその HTML をそのまま返す(`xxxHtml` は無い)。
  当初の Markdown 入力(3bmd で HTML 化)は、Quill 採用に伴い廃止した。microCMS の HTML もそのまま取り込める。
- モデルには `:preview-url` / `:public-url` のテンプレート(`{CONTENT_ID}` `{DRAFT_KEY}` を置換)を設定でき、
  編集画面に「Preview draft」(下書きがあるとき)と「Published page」(公開済みのとき)のリンクを出す。

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
settings       (key PK, value, updated_at)      ; インスタンス設定(二段階認証の鍵など)
sessions       (id PK, data JSON, expires_at)   ; 管理画面のログインセッション
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
  microCMS 互換のサブセット: `limit` `offset` `orders` `fields` `filters` `draftKey`。
  参照は常に id で返し、`include=tags,author.avatar` のように名指ししたフィールドだけ埋め込む(`depth` は持たない)。
  レスポンスは `{contents, totalCount, offset, limit}`。object 型は単一オブジェクトを返す。
  `filters` は `[equals]` `[not_equals]` `[contains]` `[exists]` `[not_exists]`
  `[less_than]` `[greater_than]` と `[and]` `[or]` の主要なもののみ。
- **管理 API**: `/admin/api/...`(実装済みのパス)。
  - `GET /admin/api/me`(疎通・認証確認)
  - `GET /admin/api/schema`(pull)、`PUT /admin/api/schema[?force=true]`(deploy)、`POST /admin/api/schema/plan`
    - deploy に破壊的変更が含まれ `force` が無い場合は `409 destructive_changes` を返し、`details` に変更一覧を載せる。
      クライアントはそれを表示して確認を取り、`force=true` で再送する(差分計算は本体側)。
  - `/admin/api/contents/{space}/{model}`: `GET`(下書き含む一覧)`POST`(`{"data": {...}, "publish": bool}`。
    移行用に `id` と `createdAt` `updatedAt` `publishedAt` `revisedAt` を任意で指定できる)
  - `/admin/api/contents/{space}/{model}/{id}`: `GET` `PATCH`(`{"data"}` を既存データにマージして下書き保存)`DELETE`
  - `/admin/api/contents/{space}/{model}/{id}/publish` `/unpublish` `/discard-draft` `/draft-key`(`POST`。
    `discard-draft` は公開済みコンテンツの下書きを捨てて `published` に戻す。未公開なら 409。webhook は送らない)
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
  UI はログインフォーム → セッション Cookie、管理 API(deploy 等)は `Authorization: Bearer`。
  比較は定数時間で行う。
- **セッションはプロセスではなく DB(`sessions` テーブル)に持つ**。再起動・再デプロイでログアウトしない。
  寿命は Cookie も行も 24 時間で、使うたびに延びる(行の書き込みは半分を過ぎてから)。値は JSON で保存する
  ため、セッションに入れてよいのは文字列・数値・真偽値とその配列だけ(flash もこの形)。
- **二段階認証(TOTP)**: 初期状態は無効。管理画面の `/settings` で「Set up」すると鍵を生成して QR コード
  (otpauth URI)とシークレットを表示し、認証アプリのコードを入力して初めて有効になる(鍵は `settings` テーブル)。
  無効化にもコードが要る。`KOYA_TOTP_SECRET`(Base32)を環境変数で与えるとそれが優先され、画面からは変更不可。
  RFC 6238(SHA-1、30 秒、6 桁、前後 1 ステップ許容)。使ったステップはプロセス内で記憶し、同じコードで二度は入れない。
  シークレットが違えばコードの正否は判定しない(コードを消費しない)。対象はブラウザのログインのみで、
  管理 API の Bearer は機械向けなので変えない。QR は同梱の qrcode.js(davidshimjs、MIT)でブラウザ側で描く。
- 配信 API: space ごとの API キー(`X-KOYA-API-KEY`)。**本体側で生成し、管理 UI に表示**する。
  利用側は `.env` に置いてクライアントへ渡す。利用側コードにシークレットを置かない。
  キーは高エントロピーの乱数なので SHA-256 ハッシュで保存する(bcrypt は使わない)。
- ningle-actions のエンドポイントも含め、管理側は全てセッション必須。CSRF は Origin ヘッダ検証。
- ログインは失敗 5 回 / 5 分でそのクライアントアドレスを一時ロック(403。Woo は 429 のステータス行を持たない)。エラー文言は二要素のどちらが違うか言わない。
  セッション Cookie は 24 時間で失効。管理 API の Bearer(`KOYA_SECRET`)は機械向けなので二段階認証の対象外
  (シークレットの漏洩はそのまま管理権限の漏洩。運用ではシークレットを長く強くし、必要なら回転する)。
- リクエスト本文は Content-Length で 21 MB を超えると最外側のミドルウェアが 413 を返す(multipart は lack が丸ごと
  メモリに読むため、パース前に止める)。Coolify 側の Traefik にも同程度の上限を置くとよい。
- webhook の URL はオーナーがスキーマで書くものなので任意(内部ネットワークにも届く)。単一オーナー前提で許容。

## 7. 管理 UI

- **Lisp フルスタック**。フロントも含めて Lisp で書く。
- SSR: hsx(HTML S 式)。SPA・JS ビルドチェーンは持ち込まない。
  HTMX と ningle-actions は配線済みだが現時点で使う画面は無い(M2 のメディアモーダルで使う予定)。
  素の JS は `assets/js/koya-editor.js` の1ファイルのみ(Quill 初期化、一覧の行リンク、複数参照のチップ UI)。
- ルーティング: ningle-fbr(ファイルベース)。
- CSS: Tailwind CSS v4(スタンドアロンバイナリ、`justfile` でビルド)。
- フォームは DB 上のモデル定義から動的生成(フィールド型 → 入力コンポーネントの対応表)。
- richtext は Quill。フォーム送信時に HTML を隠しフィールドへ書き戻す(`assets/js/koya-editor.js`)。
- 完了メッセージはセッションに載せる一度きりの flash(リダイレクト後に一度だけ表示)。
- 画面(実装済みパス): `/login`、`/`(space 一覧)、`/s/{space}`(モデル一覧。種別アイコン、list 型は件数)、
  `/s/{space}/keys`(API キー)、
  `/s/{space}/m/{model}`(コンテンツ一覧。object 型は単一コンテンツの編集画面へリダイレクト)、
  `/s/{space}/m/{model}/{id}`(編集。`{id}` = `new` で新規)。**メディアライブラリ**(8 章)は M2。
- コンテンツ一覧は作成日時の新しい順。列はモデルの全フィールドのプレビュー(richtext はタグ除去、
  参照は参照先のラベル、60 文字で省略)と status で、created / updated は出さない。
  列幅はフィールドの型ごとに下限と上限を決め、その間でプレビューを折り返す。下限があるのでフィールドが
  多いモデルは横スクロールになる。行全体が編集画面へのリンク。
- フォームは通常の POST(`action` = save / publish / unpublish / discard / delete)で送る。
  「Discard draft」は `published+draft` のときだけ出る。未公開の下書きは Delete が破棄に相当する。
- 管理側の POST は `Origin` / `Referer` が `Host` または `KOYA_BASE_URL` と一致することを要求する(CSRF 対策)。
- `:datetime` の入力は `datetime-local` で、値は UTC として扱う(タイムゾーン変換は M2 で JS を足す)。
- `:slug` はフォーム・API のどちらでも、空なら `:from` のフィールドから本体側で自動生成する(ASCII のみ)。
- `:reference` の入力は参照先モデルの全コンテンツ(下書き含む、上限 1000 件)を選択肢にした `select`。
  単一はドロップダウン、`:many` は `<select multiple>` を JS で「選択済みチップ + 追加用ドロップダウン」に置き換える
  (JS 無効時はリストボックスのまま使える)。選択肢のラベルは最初の text / slug フィールドの値、無ければ id。
  `select` の見た目はブラウザ標準(`select { all: revert }`)。
- `:media` の入力はメディアライブラリができるまで id のテキスト入力。
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
- 本体のローカルディスク(`KOYA_MEDIA_DIR`、Docker ではボリューム)に `{space}/{id}.{ext}` で保存し、
  本体自身が `/media/{space}/{id}.{ext}` で配信する(認証なし。id は使い回さないので `immutable` キャッシュ)。
  配信ミドルウェアは `space/ULID.ext` の形しか受け付けない。
- 受け付ける形式は PNG / JPEG / GIF / WebP。先頭バイトで判定し、寸法もヘッダから読む(クライアントの
  Content-Type は見ない。SVG はスクリプトを含めるため対象外)。上限 20 MB。
- リサイズ・変換・外部ストレージ(S3 等)は持たない。必要になったら CDN 側(Cloudflare Images 等)か後続フェーズで。
- フィールド型 `:media` は media の id を保存し、配信 API では常に
  `{id, url, filename, mime, size, width, height, alt, createdAt}` に展開する(削除済みなら `null`)。管理 API は id のまま。
- 管理 API: `GET/POST /admin/api/media/{space}`(`q=` 検索、`limit` / `offset`。POST は multipart の `file`(複数可)と `alt`)、
  `GET/PATCH/DELETE /admin/api/media/{space}/{id}`(GET は参照数 `references` 付き、PATCH は `{"alt"}`)。
- 管理 UI: `/s/{space}/media` がライブラリ画面。編集画面は `<dialog>` を1つ持ち、中身を ningle-actions の
  エンドポイント(`media-picker` / `media-picker-upload`、オーナーセッション必須)から HTMX で取り込む。
  `:media` フィールドの「Choose…」と Quill の画像ボタンが同じピッカーを開き、選択で id をセット、または `<img>` を挿入する。
- richtext 内の画像は `<img src="/media/...">` の URL として本文に埋め込まれる(参照数の集計はこの URL も数える)。
- client: `upload-media` `list-media` `get-media` `update-media` `delete-media`。

## 9. 下書き・公開・バージョニング

- `contents.published` と `contents.draft` の2カラム。status は `draft` / `published` / `published+draft`。
- `draftKey` でドラフトをプレビュー取得(microCMS 互換)。下書き保存のたびに draft key を再生成し、
  公開すると消す(古いプレビュー URL は無効になる)。
- **webhook** は `(webhook label url :events (...))` で定義する。space の webhook は全モデルに適用され、
  モデルは `:webhooks` で自分用を追加する(microCMS の「API ごとに複数」に相当。設定は code)。
  イベントは `:publish`(新規公開・再公開)`:unpublish` `:delete` `:draft`(下書き保存)の部分集合で、
  省略時は `:draft` 以外。ペイロードは microCMS 互換に近い形(`service`、`api`、`id`、
  `type` = `new` / `edit` / `delete` / `draft`、`contents.old/new`)。`draft` の `new` は下書きデータ。
  space ごとに生成される秘密を `X-KOYA-WEBHOOK-KEY` ヘッダで送り、受け側で照合する(秘密は webhook 単位ではなく space 単位)。
  URL 文字列だけを並べた旧形式も受け付ける(label = URL、既定イベント)。plan には label 単位で差分が出る。
- 履歴(revisions)は初期スコープ外。

## 10. 技術スタック

website(skyizwhite/website)で実績のある構成をそのまま踏襲する。

| 層 | 選定 |
|---|---|
| 実装 | SBCL、**package-inferred-system**(`src/` 配下のファイル = パッケージ) |
| 依存管理 | qlot(`qlfile`、自作ライブラリは git 指定) |
| HTTP | Clack / Lack。開発: Hunchentoot、本番: Woo |
| ルータ | jingle(ningle 拡張)+ ningle-fbr |
| 部分更新 | ningle-actions + HTMX(配線のみ。M2 のメディアモーダルから使用) |
| テンプレート | hsx |
| ミドルウェア | lack-mw(trailing-slash)、clack-errors、lack accesslog / mount / session |
| DB | cl-dbi + dbd-sqlite3 + sxql |
| JSON | jzon(com.inuoe.jzon)+ kebab(キー変換) |
| HTTP クライアント(client) | dexador |
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
- `koya/core`(バリデーション、スキーマ差分、ULID)はユニットテストを厚く。
- 本体はインメモリ SQLite(`:memory:`)でリポジトリ層と API をテスト。
- クライアントは本体をテスト内で起動して結合テスト(deploy → get-list の往復)。

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
- 環境変数: `KOYA_SECRET`、`KOYA_TOTP_SECRET`(任意)、`KOYA_DB_PATH`、`KOYA_MEDIA_DIR`、`KOYA_BASE_URL`、`KOYA_PORT`、`KOYA_ENV`。
- `GET /health`(認証なし、DB 疎通を含む)をヘルスチェックに使う。
- **キャッシュ**: `/assets/*` の URL は `?v=<assets/ 配下の最新更新時刻>` を付けて参照し、
  `public, max-age=31536000, immutable` で配る(デプロイでファイルが変わると URL も変わる)。
  `/media/*` は id を使い回さないので同じく immutable。それ以外(管理画面、管理 API、配信 API)は
  `no-store`。配信 API は API キー付きで利用側(website)が自前でキャッシュするため、中間キャッシュには載せない。

## 13. マイルストーン

### M1: website が microCMS から乗り換えられる最小構成

- `koya/core`: schema plist、フィールド型(text / textarea / richtext / datetime / boolean)、
  バリデーション、JSON シリアライズ、ULID。
- 本体: マイグレーション、schema deploy/pull/plan、contents CRUD、公開/下書き、`draftKey`、
  配信 API(`limit` `offset` `orders` `fields` `filters[equals]`)、API キー、webhook、
  管理 UI(ログイン、一覧、編集、公開)。
- client: `defspace` `defmodel` `plan` `deploy` `pull` `get-list` `get-item` `get-object`。
- 完了条件: website の `lib/cms.lisp` を koya client に差し替え、blog / about / works が動く。
- **完了(2026-09-20)**。website は `koya-migration` ブランチでローカル koya に対して動作確認済み。
  本番(Coolify)へのデプロイと本番へのスキーマ反映・インポートは未実施。

### M2: 残りのフィールド型とメディア

- 済: `:number` `:date` `:select` `:slug` の型と入力、`:reference`(select 入力、`include` 展開、
  一覧でのラベル表示)、`filters` の残りの演算子、作成時のシステム日時の指定(移行用)、
  メディアライブラリ(8 章: アップロード、`/media/...` 配信、管理 API、管理画面、編集画面のピッカー、
  Quill の画像挿入、`:media` の API 展開、client)。
- 残: `:datetime` 入力のタイムゾーン変換 JS、`docs/SCHEMA.md` と `docs/openapi.yaml` の整備。

### 2026-09-20 のコードレビューと対応

core / server / UI・client を通しでレビューし、確認できた問題は当日中に修正した(1件ずつコミット)。

- 配信 API の数値 `filters` が `*read-eval*` 有効のまま `read-from-string` していた(任意コード実行)→ 標準構文・`*read-eval*` 無効・値全体が1つの数値であることを要求。
- 一意制約チェック / object 型の1件判定と INSERT がトランザクション外 → create / update-draft / publish を `with-db-transaction` で包む(接続ロックも保持)。
- セッション Cookie に HttpOnly / SameSite が無かった → HttpOnly、SameSite=Lax、`KOYA_BASE_URL` が https なら Secure。
- 管理 JSON API が Origin を見ていなかった → 書き込みメソッドはフォームと同じ同一オリジン判定を通す(Origin 無しの非ブラウザは通る)。
- 同一オリジン判定: quri の既定ポート補完で Host と食い違う、`Origin: null` が「無し」扱い → 既定ポートを落として比較、パース不能な Origin は不一致。
- `$` アンカーが末尾改行を許す → `\z`。暦上無効な日付で 500 → 型エラー。datetime は時刻とゾーン(`Z` / オフセット)必須に。
- `false` / `[]` が全型で空扱い → boolean 以外の `false`、単一値フィールドの `[]` は型エラー。
- option 値の型未検査(壊れた正規表現で以後の保存が全滅)→ `make-field` で型検査と正規表現のコンパイル。`jobject->schema` は型・kind・option 名を許可リストから探し(intern しない)、形の不一致は `schema-error`。
- diff が `equalp` で大小文字の変更を見逃す → `equal`。required / unique / integer の追加、単一↔複数、max-length 短縮、pattern 変更、min / max の狭まり、select option の削除は破壊的変更として `:force` を要求。
- `1.5` が `1.5d0` と表示され再保存で消える → 数値は指数表記なしで出力。
- client の `lisp->jvalue` が NIL を `[]` にしていた → NIL は `null`、空配列は `#()`。
- 管理 UI: `/new` への delete / unpublish が 500 → 404。keys ページの delete / rotate → flash 付きリダイレクト(create は平文キーを一度だけ見せるため直接描画のまま)。
- hsx: 属性値のエスケープが `"` のみ → `&` も(`<` `>` は引用符内で合法なので Alpine.js の式の読みやすさを優先して据え置き。skyizwhite/hsx 側で修正。koya は push 後に `qlot update hsx` で取り込む)。

### M3: 運用・拡張

- revisions、`backup`、Slynk 接続手順、非 Lisp クライアント(TypeScript)の着手。

### 次にやること(2026-09-20 時点)

koya は cms.skyizwhite.dev、website は skyizwhite.dev に本番デプロイ済み。microCMS からのインポートを残して移行はほぼ完了。

- ~~**ドキュメント整備**~~(2026-09-21 完了): 利用者向けに `docs/ADMIN-UI.md`(管理 UI)、`docs/CLIENT.md`
  (ライブラリ)、`docs/SCHEMA.md`(スキーマ JSON の仕様、`koyaSchema: 1`)、`docs/openapi.yaml`
  (配信 API / 管理 API)を書き、README は要約とリンクに絞った。DESIGN.md は経緯込みの設計書として残す。
- 運用: `/data` ボリュームのバックアップ確認(Coolify のボリュームバックアップ、または `VACUUM INTO` の
  `POST /admin/api/backup`)。microCMS 解約後に website の `MICROCMS_*` と `scripts/import-from-microcms.py` を削除。
- ~~管理 UI: `:datetime` 入力のタイムゾーン変換~~(2026-09-21 完了。JS ではなくサーバ側で変換: 設定画面で選ぶ IANA 名の
  タイムゾーンを `settings` に保存し、`lib/timezone` が local-time で表示・入力を変換。保存と配信は UTC のまま)。
  ~~一覧のページング~~(2026-09-21 完了。100 件/ページ、`?page=`)。
- ~~セキュリティ: 管理 API 用に `KOYA_SECRET` と別のトークン~~(2026-09-21 完了。鍵は owner / management /
  delivery / webhook の 4 種。management key は Settings で発行、`management_keys` に SHA-256 保存、
  管理 API の Bearer はこれのみ。`KOYA_SECRET` はログイン専用に。クライアントは `:management-key` /
  `KOYA_MANAGEMENT_KEY`。0.2.0)。webhook 単位の秘密(`:secret`)は受け口が増えたときに。
- 2026-09-21: webhook の `:events` は必須(既定値と URL 文字列の省略形を廃止)。`:boolean` の `:default t` を
  新規作成時に適用。参照中のメディアは削除拒否(409 `in_use`)。
- 配信: webhook は通知ごとにスレッドを起こすので、大量インポート時はキューにまとめる。
- 依存: hsx の `&` エスケープ修正は koya で取り込み済み。website は `qlot update koya` で koya の変更を追従。

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
| 2026-09-20 | Webhook は space ごとの秘密を `X-KOYA-WEBHOOK-KEY` で送る(管理 UI で表示・ローテート) | 受け側が呼び出し元を検証できるようにする |
| 2026-09-20 | 作成・公開時に `id` と `publishedAt` を明示指定できる。参照 id は URL セーフ文字列なら可 | microCMS からの移行で URL と公開日を維持する |
| 2026-09-20 | 作成時は `createdAt` `updatedAt` `revisedAt` も明示指定できる | microCMS の 4 つのシステム日時をそのまま持ち込む。未指定は現在時刻 |
| 2026-09-20 | website の移行は `koya-migration` ブランチで実施(ローカル koya で全ページ表示を確認) | M1 完了条件 |
| 2026-09-20 | richtext は Quill で編集する HTML 文字列に変更(Markdown / 3bmd 廃止) | 管理 UI の使い勝手。microCMS の HTML をそのまま移行できる |
| 2026-09-20 | モデルに `:preview-url` / `:public-url` テンプレート、draft key は保存ごとに再生成、flash はセッション一度きり | 管理 UI 改善の要望 |
| 2026-09-20 | 参照の展開は `depth` ではなく `include`(フィールド名指し、`a.b` で入れ子)。デフォルトは id のみ | 必要な参照だけ取る。深さ指定は不要な展開を招く |
| 2026-09-20 | 管理 UI の一覧は全フィールドのプレビュー + status、行全体がリンク。reference は select(複数はチップ + ドロップダウン)、見た目はブラウザ標準 | 一覧で内容を判断できるように。参照 id の手入力をやめる |
| 2026-09-20 | 運用ツール(website の schema 同期など)は just コマンドではなく REPL から呼ぶ Lisp 関数として提供する | REPL 駐在で開発するため |
| 2026-09-20 | JSON の `false` / `[]` は「値」。空扱いは `null`・空白文字列・`:many` の `[]` のみ | jzon が false を NIL にするため、型の取り違えを保存しない |
| 2026-09-20 | 制約を強める field option 変更(required 追加、単一↔複数、pattern 変更など)は破壊的変更 | 既存コンテンツを不正にしうる変更は `:force` で自覚的に |
| 2026-09-20 | 管理 API の書き込みも Origin 検証。Cookie は HttpOnly / SameSite=Lax / https なら Secure | SameSite の既定値だけに頼らない |
| 2026-09-20 | メディアは koya 自身が `/media/` で配信。形式は先頭バイトで判定し PNG / JPEG / GIF / WebP のみ、SVG は不可 | 外部ストレージなしで完結させる。Content-Type 詐称と SVG 経由のスクリプトを避ける |
| 2026-09-20 | `:media` は配信 API で常にオブジェクト展開(`include` 不要) | 画像は URL が無いと使えず、展開が入れ子になることもない |
| 2026-09-20 | 二段階認証は TOTP。管理画面の設定ページで有効化し鍵は `settings` テーブルへ。`KOYA_TOTP_SECRET` は上書き用 | REPL より画面の方が親切。初期無効で、アプリのコード確認を経て有効化 |
| 2026-09-20 | webhook は label / url / events を持ち、space(全モデル)とモデルの両方に定義できる。秘密は space 単位のまま | microCMS の API 単位・イベント設定を code で取り込む。下書きイベントでプレビュービルド等を回せる |
| 2026-09-20 | `defmodel` の `:kind` は必須(`:list` / `:object`)。省略はマクロ展開時にエラー | 既定値があると list か object か読み手に分からない |
| 2026-09-20 | セッションはメモリストアをやめ SQLite の `sessions` テーブルに置く(24 時間、使うたび延長、起動時に期限切れを掃除) | 再起動・再デプロイのたびにログアウトしていたため |
| 2026-09-20 | 配信 API の互換ヘッダ `X-MICROCMS-API-KEY` を廃止。デプロイ前レビューで本文サイズ上限・ログインロック・セッション失効・空セッション非保存を追加 | 他社名を残さない。本番公開前に DoS とブルートフォースの入口を塞ぐ |
