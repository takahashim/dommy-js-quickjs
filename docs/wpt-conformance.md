# WPT 適合性 (conformance)

`test/fixtures/wpt/` にベンダリングした Web Platform Tests コーパスを、`WptRunner`
(`test/support/wpt_runner.rb`) でブリッジに対して実行し、適合率を報告する:

```
bundle exec rake wpt:conformance          # コーパス全体
bundle exec rake "wpt:conformance[url]"    # パス部分文字列でフィルタ
```

`WptRunner` は WPT の 2 つのファイル形式を扱う。`.any.js` / `.window.js` スクリプト
(`// META: script=` インクルードを解決し、`fetch("resources/…")` のデータファイルを
fetch スタブ経由でディスクから配信する) と、`.html` テスト (ファイル自体が document
となり、インライン `<script>` ブロックがテスト本体、testharness 以外の
`<script src>` ヘルパーはベンダリングしたツリーから解決する)。synthetic な `load`
イベントが testharness の完了をどう駆動するかは `WptHarness` を参照。

## スナップショット (2026-05-30、WHATWG basic URL パーサー + Element *AttributeNS の後)

```
  dom       997/2261  (44.1%)
  url        91/109   (83.5%)
  total    1088/2370  (45.9%)   — 9 ファイルが完全グリーン
```

セッション開始時の 108/2370 (4.6%) からの伸び。内訳:
- URL コアの書き直し (下記) が `url` を 77.1%→83.5% に。`dom` には影響しない (url 専用)。
- Element `*AttributeNS` の実装が `attributes.html` を **7→22/67** に上げ、`dom` を
  982→997 に押し上げた (+15 = ちょうど attributes の増分)。

残る `dom` の不足は `Document-createElementNS.html` (1/596) と
`Document-createElement.html` (0/147) に集中しており、いずれも名前空間 / 大文字小文字 /
バリデーション作業が必要。加えて `attributes.html` の残り (22/67、後述。大半はブリッジ側の
NamedNodeMap/Attr ギャップ) と、雑多な `Element-classlist` のテール (~965/1420) がある。

## Landed (2026-05-30 セッション)

- **WHATWG basic URL パーサー** (Dommy, `Internal::UrlParser`)。`Dommy::URL` の
  Ruby-`URI` コアを仕様準拠のステートマシンパーサーに置き換えた (`Record` 構造体、
  階層パス vs opaque パス、ホスト解析は既存の `Internal::IDNA` / `Ipv4Parser` /
  `Punycode` を再利用、percent-encode セット一式)。`Dommy::URL` は `@record` を
  ラップするようになった。`urltestdata.json` に対する純 Ruby 計測:
  **496/887 → 887/887 (100%)**。100% に到達する過程で取り込んだバグ修正:
  opaque パスの末尾スペースのエンコード (次が `?`/`#` のときのみ `%20`)、path
  percent-encode セットに `^` (0x5E) を含める、`parse_host` で UTF-8 デコード時に
  U+FFFD で置換 (`%80`/`%A0` ホストが `ArgumentError` でなく綺麗に失敗する)、
  `IDNA.to_ascii` に WHATWG パラメータ追加 (`check_hyphens: false`,
  `verify_dns_length: false` → 空 / 過長 / ハイフン端のラベルを許容、例
  `http://./`、`http://foo.09..`)、`Ipv4Parser` が裸の基数接頭辞 (`0x`、`0`) を 0 と
  みなす (`https://0x.0x.0x.0x` → `0.0.0.0`)。dommy 全スイートグリーン (2507) +
  quickjs (113)。→ url-statics-tojson 1/1、urlsearchparams-stringifier 14/14;
  `url-constructor`/`url-origin` は依然 0/1 (データ駆動、後述)。
- **URLSearchParams `sort`** (Dommy): 名前を UTF-16 *コードユニット* 順でソートする
  ようにした (サロゲートペア文字は先頭の 0xD800–0xDBFF ユニットで並ぶ)。同名は
  index タイブレークで安定 (Ruby の `sort_by` は安定でないため)。
  → urlsearchparams-sort 13/17 → **17/17**。
- **Element `*AttributeNS`** (Dommy)。`getAttributeNS` / `setAttributeNS` /
  `hasAttributeNS` / `removeAttributeNS` / `getAttributeNodeNS` /
  `setAttributeNodeNS` を実装し、`__js_call__` に配線。新しい
  `Internal::Namespaces.validate_and_extract` が WHATWG DOM の "validate and
  extract" を実装 (NCName/QName 検証 → InvalidCharacterError、prefix と
  namespace の整合性 → NamespaceError、`xml`/`xmlns` の特例)。両バックエンドが NS
  ストレージを実装 (Nokogiri はフル NS、Nokolexbor は null 名前空間に縮退)。仕様の
  「set an attribute value」修正も含む — 既存の (namespace, localName) 属性を別 prefix
  で再 set したとき、値のみ変更し prefix は保持する (以前は prefix が変わっていた)。
  → attributes.html **7→22/67**、dom 982→997。残りはブリッジ側ギャップ (後述)。
- **Promise thenable adoption** (ブリッジ + Dommy)。`HostBridge#invoke_callback` /
  `invoke_lifecycle` が戻り値を `unwrap` するようになり、JS の `.then` コールバックが
  返した Promise プロキシが生きた `PromiseValue` として戻る。また
  `Dommy::PromiseValue` の adoption 継続が `self` を返さなくなった (`run_handler`
  が無限に再 adopt していた — microtask 無限ループ)。結果:
  `fetch().then(r => r.json()).then(data …)` チェーンが値を届けるようになった。
- **URLSearchParams** (`Dommy::URLSearchParams`):
  `append`/`set`/`has`/`get`/`getAll`/`delete` 全体で `null`→`"null"` の USVString
  強制変換; 2 引数の `has(name, value)` / `delete(name, value)`; パーサが空の `&`
  トークンをスキップ; `forEach` は JS コールバックをブリッジ ABI 経由で呼ぶ
  (`&block` ではなく); WHATWG `application/x-www-form-urlencoded` シリアライザ
  (`*-._` を保持、スペース→`+`)。
  → append 4/4、stringifier 14/14、has 3/4、delete 5/8、foreach 2/6; url
  68.8%→77.1%。
- **`URL.parse` がもう throw しない** ("both relative" ケース): `parse_with_base` が
  `URI::Error` (`URI::BadURIError` 含む) を rescue → `SyntaxError` → `nil`。
- **DOMException マーシャリング** (ブリッジ)。ホスト RPC の本体
  (`__rb_host_get/call`、`__rb_construct`、`__rb_static_call`) を `dom_guard` 内で実行
  し、`Dommy::DOMException` を捕捉してタグ付きマーカーを返す; JS 側の `rehydrate` が
  それを本物の `DOMException` として再 throw する (name + legacy code、`instanceof
  DOMException`)。以前は quickjs gem がプレーンな `Error` に潰していたため、すべての
  `assert_throws_dom` が失敗していた。非子要素の `removeChild` (NotFoundError、code 8)
  をはじめ、あらゆる DOM のエラー契約を修正。(その `Element-classlist` への効果は、下記
  の PutForwards 修正までマスクされていた — throw する呼び出し自体がメソッドを解決でき
  なかった。)
- **`classList` PutForwards** (Dommy)。`el.classList = x` が class 属性へ転送される
  ようになった (`Element#__js_set__` が `"classList"` を扱う)、WHATWG
  `[PutForwards=value]` 準拠。以前は未処理の write が JS 側の文字列 expando になり、
  その要素の生涯にわたって **`classList` ゲッターをシャドウ** していたため、以後の
  `el.classList.add(…)` がすべて文字列を見ていた (`list[fn]` が undefined)。→
  **Element-classlist 20→965/1420**、dom 1.5%→43.4%、total 4.9%→**45.0%**。
- **`nodeName`** (Dommy): `Text`→`"#text"`、`Comment`→`"#comment"` (および
  `#cdata-section`)、`DocumentFragment`→`"#document-fragment"`、`DocumentType`→
  その name。→ Node-nodeName 1→5/6 (残り: 外来名前空間の要素の大文字小文字)。

### `url-constructor` / `url-origin` は依然 0/1 (データ駆動ハーネスのギャップ)
URL の *コア* はもうボトルネックではない — パーサは純 Ruby で `urltestdata.json` の
887/887 を通す。この 2 ファイルが 0/1 のままなのは、ハーネスがそのコーパスをブリッジ
経由で流し込めないため:

1. **`Response#json` が lone surrogate を拒否する。** WPT の `urltestdata.json` には
   `\uD800` のようなエスケープが含まれ、Ruby の `JSON.parse` が "invalid surrogate
   pair" で例外を投げ、どのケースが走るより前に `promise_test` 全体を落とす。(Ruby の
   UTF-8 文字列は lone surrogate を保持できないので要注意 — JS 側で parse するか、寛容な
   デコーダが必要。)
2. **マーシャリング: "Node object of unknown type"。** JSON ロードを越えても、
   `promise_test` がブリッジからこれで reject する — fetch/デコードしたコーパスの行が
   host↔JS 境界を綺麗に越えられていない。~887 件の constructor ケースがハーネス経由で
   実際に走るには、この両方を解決する必要がある。

(ここにあった歴史的なメモ — 「`Dommy::URL` は ~56% WHATWG 適合、496/887」 — は
**解決済み**: Landed の WHATWG basic URL パーサーを参照。)

## 残りのギャップバックログ (ROI 順)

大半は Dommy 側; ブリッジ側は明記する。

### URL コア — WHATWG basic URL パーサー — **完了** (Landed 参照)
- Ruby-`URI` を `Internal::UrlParser` に置換; `urltestdata.json` で 887/887。
- これ単体では解消しなかったもの: `url-constructor`/`url-origin` は依然 0/1。今は
  ハーネスのデータ供給の問題 (`Response#json` の lone-surrogate + "Node object of
  unknown type" マーシャリング — 上記) がボトルネックで、パーサではない。これらの修正が
  次に大きい `url` レバー (1 つの `promise_test` の裏に ~887 ケースが隠れている)。

### Element `*AttributeNS` — ロジックは完了、ハーネスはブリッジ側でブロック
- **AttributeNS のロジックは正しい** (純 Ruby で直接検証: get/set/has/remove、すべての
  名前空間規則、validate-and-extract のエラー (NamespaceError / InvalidCharacterError)、
  大文字小文字保持; dommy ユニットテスト 12/12 グリーン; prefix 保持バグを 1 件発見 &
  修正)。attributes.html を 7→22/67 に上げた。
- 残り 45 件の失敗は **大半がブリッジ側 / 非 NS のギャップ** であり、AttributeNS の
  ロジックではない:
  - **NamedNodeMap のインデックスアクセス + Attr ノードのインターフェース** (~30 件)。
    多くのテストが `el.attributes[i]` / `.item(i)` を読むか、Attr ノードオブジェクト
    (`getAttributeNode`/`setAttributeNode`/`removeAttributeNode` とその NS 版) を操作
    し、ヘルパー `attr_is` で属性メタデータを検査する。これらが "(object) null"
    (インデックスアクセスが null を返す) や "Node object of unknown type" (Attr ノードが
    識別可能なインターフェースとしてマーシャルされない) で落ちる。これがブロッカーの主因。
  - **非 NS の `setAttribute` / `toggleAttribute` の Name production バリデーション**
    (2 件)。不正な Name で INVALID_CHARACTER_ERR を投げるべき (NS パスは
    validate_and_extract が処理するが、非 NS パスは未検証)。
  - **NamedNodeMap の own-property 列挙** (6 件)。`Object.getOwnPropertyNames(
    el.attributes)` がインデックス名 (`["0","1",…]`) と qualified name を返すべき。
    ブリッジ側のプロキシ own-property のギャップ。
  - `document.implementation.createDocument` 未実装 (1 件)、`toggleAttribute` の順序 /
    inline style の扱い等。
- 言い換えると、NamedNodeMap の indexed/item 越境と Attr インターフェースのマーシャ
  リングを実装すれば、AttributeNS のロジックはすでに正しいので大量に green に転じる。

### `Element-classlist` の残り (965/1420)
- liveness バグではない — `Dommy::ClassList` はすでに毎回 `class` 属性を新鮮に読む。
  ジャンプは PutForwards + DOMException マーシャリング (上記) によるもの。残り ~455 件は
  雑多なテール: `MutationObserver` レコードのタイミング/内容、値の不一致、`DOMTokenList`
  の `supports`/イテレーション / `not a function`、`did not throw`、外来名前空間
  (SVG/MathML) ケース。優先度低。

### createElement / createElementNS / 名前空間
- `createElementNS` の非 HTML 名前空間は大文字小文字を保持すべき:
  `createElementNS(SVG, "svg").nodeName` は `"svg"` のままで、大文字化されてはならない;
  SVG/MathML/その他名前空間の `tagName` も同様。
- 不正な qualified name (HTML document 文脈での `"x:b"`、空の name、不正なプロダクション)
  は `DOMException` `InvalidCharacterError` / `INVALID_CHARACTER_ERR` を投げるべき。
  (注: NS パスは `Internal::Namespaces.validate_and_extract` で済むが、`createElement` の
  非 NS パスは Name production の検証が必要。)
- `createElement(undefined)` パスは `HTMLUnknownElement` がシードされたインターフェース
  として存在することを期待する (テストが `instanceof` を行う → "invalid instanceof right
  operand")。

### ノードの命名 / ノードタイプ — 完了 (Landed 参照)
- `Text`/`Comment`/`DocumentFragment`/`DocumentType` の `nodeName` は修正済み。残る
  Node-nodeName の失敗 1 件は外来名前空間の *要素* の大文字小文字で、上記の
  createElementNS 項目に属する。

### Attributes (NamedNodeMap / Attr のブリッジ側)
- `el.attributes[i]` / `.item(i)` のインデックスアクセスと Attr ノードのインターフェース
  マーシャリング (上記 `*AttributeNS` 項目の主ブロッカー)。
- 非 NS の `setAttribute` / `toggleAttribute` で不正 qualifiedName → `INVALID_CHARACTER_ERR`。
- `getAttributeNames` の重複/名前空間付き属性のカウント。

### URLSearchParams (このセッション後の残り)
- `sort` — **完了** (UTF-16 コードユニット順、安定; 17/17)。
- コンストラクタ: sequence-of-sequences のバリデーション (`new URLSearchParams([[1]])`
  は throw すべき)、unpaired-surrogate の扱い。
- ライブな `for…of` イテレーション (urlsearchparams-foreach 2/6): イテレータは各ステップで
  pairs を読み直す必要がある — ループ中の `url.search` 変更や `delete` が見えなければ
  ならない。現在ブリッジは `for…of` に `entries` のスナップショットを渡すため、"For-of
  Check" / "delete … during iteration" ケースは古い pairs を見る。ブリッジに **ライブ
  イテレータプロトコル** (`.next()` ごとに Ruby へコールバックするステートフルな index)
  が必要で、単なる `ENTRIES_ITERABLES` では不十分。

### 末尾の optional 引数での `undefined` vs `null` (ブリッジ) — 6 subtests に波及
- `URL.parse("aaa:b", undefined)` / `URL.canParse("aaa:b", undefined)` は `undefined` を
  「base なし」として扱うべき (→ parse 成功)、`has(name, undefined)` /
  `delete(name, undefined)` は 1 引数形と同じ挙動になるべき。純 Ruby の `Dommy::URL` /
  `URLSearchParams` は `nil` の base/value を正しく扱える; ギャップは、ブリッジが JS の
  `undefined` と `null` の **両方** を Ruby `nil` にマーシャルすること (`dehydrate` が
  primitive をそのまま返し、quickjs gem が両者を `nil` に畳む)。そのためディスパッチが
  「不在」(`undefined`) と明示的な `null` 値 (WebIDL の USVString 変換で `"null"` になる)
  を区別できない。修正には、ブリッジが `undefined` を区別して運ぶ仕組み (例えば
  `dehydrate`/`unwrap` での `{__rb_undefined: true}` センチネル) が必要で、optional 引数の
  ディスパッチが末尾の `undefined` を落とせるようにする。ブリッジ側; URL 以外にも波及。

### 計測 (後で、今はやらない)
- **スコープを絞った `idlharness` 試行。** WPT の `idlharness.js` は WebIDL の正準的な
  クロスチェックだが、測るのは *構造的* な忠実度 (インターフェース/継承、属性/メソッドの
  存在、**プロパティ記述子 + プロトタイプ同一性**) — ES6-Proxy + 合成プロトタイプの設計は
  後者を意図的に近似しているため、フル実行は記述子ノイズが支配的になる。値の強制変換の
  バケット (`ToString(null)`、`long`/`USVString`/enum) はメソッド単位のテスト (すでに
  走らせているもの) でより良く測れる。いつか構造的バケットをデータで定量化するために
  スコープを絞った実行 (URL/URLSearchParams か Node/Element/Event) をする価値はあるが、
  メソッド単位のバックログより優先ではない。

### インターフェース / より大きな機能 (優先度低)
- `NodeList` インターフェースのシード (getElementsByClassName のインターフェースチェック)。
- `document.implementation.createDocument` / 外来 document / `createDocumentType` —
  `Node-isEqualNode` と WPT の `dom/common.js` のセットアップに必要 (それらのテストは
  セットアップがこれ無しでは throw するため、まだベンダリングしていない)。
- `DocumentFragment#childNodes` / `Document` ノードの dehydration / "Illegal
  constructor" — **ブリッジ側** の dehydration + インターフェースカバレッジ。
- **Proxy `set` トラップが読み取り専用のホストゲッターを expando でシャドウする。** Dommy
  が write を処理しないとき、ブリッジはターゲットに JS 側 expando を退避する; そのプロパティ
  が実際にはホストの *ゲッター* (例 `classList`、`tagName`) だと、expando が以後それを恒久的
  にシャドウする。`classList` は Dommy の PutForwards で回避したが、一般則として誤り —
  ホスト公開の読み取り専用 name への未処理 write はドロップ (または strict モードで throw)
  すべきで、シャドウすべきでない。ホストが「この name は自分が所有する (読み取り専用)」 vs
  「自由な expando スロット」を通知する必要がある。
- **Proxy `has` トラップがすべてに `true` を返す** (`host_runtime.js` の
  `has() { return true; }`)。そのため `"nodeType" in anyProxy` が true になり、ダック
  タイピングを欺く (testharness の `is_node` が無関係な値を "Node object of unknown type"
  と整形する)。これまで見た失敗では cosmetic だが、潜在的な正しさのバグ: プロキシ上の
  `in` / `with` が嘘をつく。実際のメンバーシップ (symbols/HKEY/メソッド/expando/
  プロトタイプ) に厳格化すべき — ただし正当に null な DOM プロパティ (`firstChild`) に注意
  すべきで、get ベースのヒューリスティックだけでは不十分。
