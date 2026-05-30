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

## スナップショット (2026-05-31、encoding SharedArrayBuffer + ストリーミング BOM の後)

```
  dom        6788/7561  (89.8%)   — うち querySelector-All 1559/1977, Element-matches 536/672, dom/abort 34/37
  url        1390/1396  (99.6%)
  encoding    174/178   (97.8%)
  domparsing   68/100   (68.0%)
  html         64/95    (67.4%)
  total      8484/9330  (90.9%)   — 97 ファイルが完全グリーン
```

> **encoding を 118→174/178 (97.8%) に +56** (encodeInto 56→110/111、textdecoder-copy 0→2、
> encoding 全体 +56)。(1) **WebAssembly.Memory polyfill** (`runtime.rb` の
> `install_browser_globals`): QuickJS は本物の `SharedArrayBuffer` を持つが `WebAssembly` が
> 無く、WPT の `common/sab.js` は SAB コンストラクタを
> `new WebAssembly.Memory({shared:true}).buffer.constructor` から導出する。`.buffer` が
> SharedArrayBuffer の最小 Memory を生やすだけで、SAB を使う encodeInto/textdecoder-copy が
> 本物のコーデックロジックで走る。(2) **SharedArrayBuffer の dehydrate** (`host_runtime.js`):
> SAB は `instanceof ArrayBuffer` が false なので別途バイト列として渡す。(3) **ストリーミング BOM 除去
> をバイトレベル→コードポイントレベルに** (`text_codec.rb` `decode_utf8`): BOM が複数の `decode()`
> 呼び出しに跨る (EF BB → BF) と 3 バイト prefix チェックでは捕まらないので、デコード後に先頭 U+FEFF を
> 除去する「BOM seen」フラグ方式に変更 (ストリーミング跨ぎで持続・flush でリセット)。残り 4 件は backend
> 上限/範囲外 (ArrayBuffer detach ×2、Big5 ×2)。WebAssembly polyfill はグローバルだが回帰ゼロ。

> **querySelector/matches/closest のセレクタ検証を強化 → +68 subtests** (querySelector-All 1505→1559、
> Element-matches 522→536): (1) **引数なし → TypeError** (args.length で判定)、(2) **空文字列 →
> SyntaxError**、(3) **先頭がコンビネータ (`>*` 等の相対セレクタ) → SyntaxError**、(4) **未知の
> pseudo-class → SyntaxError** (既知 pseudo の全集合 `KNOWN_PSEUDOS` と照合; `:hover` 等の既知だが
> 未実装は valid=空マッチ、`:example` 等の未知は invalid)。Nokogiri が黙って受理する無効セレクタを
> spec 通り弾く。残りの querySelector 失敗 (~400) は Nokogiri の CSS3 パーサが `[attr*=v]`/`[attr=v i]`
> 等を parse できない backend 上限 (別のセレクタエンジンが必要)。
>
> 直前: **dom/abort 17→34/37** + **不透明 JS 値の identity 保持** (96 green)、**html/dom ARIA reflection**。

> **dom/abort 17→34/37 (91.9%)、3 ファイル green** + **ブリッジの identity 制約を解消**: AbortSignal の
> reason undefined (非abort時)、`abort()`/`abort(null)`/`abort(undefined)` の区別 (args.length)、
> `AbortSignal.timeout` を win.scheduler に、`onabort` イベントハンドラ、abort イベントの isTrusted。
> **核心 = 不透明 JS 値の round-trip**: 非 plain な JS オブジェクト (Error/DOMException/クラスインスタンス
> = prototype ≠ Object.prototype) が Ruby に渡ると Hash 化され **identity を失っていた** (さらに Error は
> enumerable プロパティ無しで空 Hash に)。dehydrate でこれらを **不透明な JS-side ref** として渡し、
> Ruby は `Bridge::JSValue` として保持、戻すと元の JS オブジェクトに復元 → `signal.reason === reason` が成立
> (plain `{}` は従来通り Hash なのでオプションバッグは無影響)。`Bridge::ThrowValue` で throwIfAborted が
> 正確な reason を throw。**回帰ゼロで +7 subtests・+3 green** (CustomEvent detail 等にも波及)。残り 3 =
> dependent-signal の abort 順序 (flattening が必要) + iframe (範囲外)。
>
> 直前: **html/dom ARIA reflection** (属性 44/44 + 要素 8/27)、**MutationObserver** (6 green)、**dom/lists** (189/189)。

> **html/dom ARIA reflection**: **属性 (string) reflection 44/44 green** (aria-attribute-reflection
> 41/41 + tentative 3/3) — `ariaXxx`↔`aria-xxx`、`role`↔`role` の nullable DOMString。**要素参照
> reflection** も実装 (aria-element-reflection 0→8/27、disconnected 1/2): `ariaActiveDescendantElement`
> ↔ `aria-activedescendant` (単数=Element)、`ariaDescribedByElements`↔`aria-describedby` (複数=Element
> 配列)。explicit ref / IDREF 解決 (要素の root subtree でスコープ、切断後も有効)、setAttribute/
> removeAttribute で explicit ref クリア。**named element access** (`<div id=foo>`→裸の `foo`) はハーネスで
> id 要素を globalThis に mirror して近似。途中で**ブリッジ一般バグ修正**: JS `undefined` の **set 値**が
> `:undefined` シンボルで渡り Bridge::UNDEFINED と別物だった→unwrap で正規化。aria-element の残り 19 は
> shadow-DOM のアクセシビリティスコープ検証 (複雑な別機能)、labelledby は `test_driver.get_computed_label`
> 依存で範囲外。`window` に JS 組み込み公開 + accessKeyLabel。reflection.js 系は 60s VM タイムアウトで未 vendor。
>
> 直前: **MutationObserver 複数改善** (6 ファイル green)、**dom/lists** (189/189)、**dom/collections** (50/53)。

## (旧) MutationObserver 改善

> **MutationObserver を複数改善** (dom/nodes MO 6 ファイル green): (1) **配信タイミングをブリッジ側で修正** —
> dommy の host-side microtask (Ruby scheduler) を native の promise ジョブキューに統合し、
> `await Promise.resolve()` と FIFO で interleave。(2) **childList レコードの type フィルタ** —
> `childList:false` の observer に childList レコードを配信していたバグを修正。(3) **observe を target の
> document に登録** — DOMParser 製 XML doc の要素の変更も届くように。(4) callback `this`=observer、
> MutationObserverInit を JS ToBoolean 評価。→ textContent 1→4 (green)、attributes 41/42、sanity・
> callback-arguments green。残りの MO はタイミングではなく backend 限界 (libxml2 隣接テキスト merge =
> fragment/normalize、Range op の characterData レコード未発火、unprefixed-ns 属性、parser 観測)。
>
> 直前: **dom/lists** (189/189, 100%)、**dom/collections** (50/53)、**dom/observable** (187/241)。

## Landed (2026-05-31 セッション)

- **querySelector/matches/closest セレクタ検証** (Dommy)。**+68 subtests** (querySelector-All
  1505→1559、Element-matches 522→536、回帰ゼロ、total 90.3% 突破)。`Internal.validate_selector!` を
  全 query 系 (Element/Fragment/Document/NodeWrapperCache の querySelector(_all)、matches?、closest) で
  呼び、空文字列・先頭コンビネータ・未知 pseudo-class を SyntaxError に。引数なしは各 __js_call__ dispatch
  で `args.empty?` → Bridge::TypeError。未知 pseudo は `KNOWN_PSEUDOS` 全集合と照合 (属性セレクタ/文字列/
  エスケープを含むセレクタは backend に委譲して誤検出回避)。残りは Nokogiri CSS3 パーサ上限。

- **dom/abort + 不透明 JS 値の identity 保持** (bridge + Dommy)。dom/abort **17→34/37 (91.9%)、3 green**。
  - **AbortSignal/Controller の細部**: reason は非abort時 undefined; `abort()` (引数なし) はデフォルト
    AbortError、`abort(null)` は null、`abort(undefined)` はデフォルト — `args.length` で区別 (NO_REASON
    センチネル); `AbortSignal.timeout` に win.scheduler を渡す (旧: win で set_timeout 無し); `onabort`
    イベントハンドラプロパティ (add/remove_event_listener 経由); abort イベントの `isTrusted=true`
    (Event#__internal_mark_trusted__)。
  - **核心: 不透明 JS 値の round-trip (ブリッジ一般機能)**: 非 plain な JS オブジェクト (prototype が
    Object.prototype でも null でもない = Error/DOMException/Map/クラスインスタンス) は dehydrate で
    **JS-side レジストリに登録し `{__rb_js_ref: id}` として**渡す。Ruby は `Bridge::JSValue` (id 保持) として
    扱い、wrap で `{__rb_js_ref}` → rehydrate でレジストリから**元の JS オブジェクトを復元** (identity 保持)。
    plain `{}` データオブジェクトは従来通り key→value マップなのでオプションバッグは無影響。これで
    `controller.abort(error); signal.reason === error` や CustomEvent detail の identity が成立。
  - **`Bridge::ThrowValue`** (< RuntimeError): host メソッドが任意の値を JS に throw する機構
    (`throwIfAborted` が文字列/数値/JSValue の reason を verbatim throw)。dom_guard が `{__rb_throw__}` に
    タグ付けし JS rehydrate が re-throw。Exception reason (デフォルト AbortError) は従来通り直接 raise。
  - 残り 3: AbortSignal.any の abort 順序 (dependent-signal を root に flatten + mark-then-fire が必要、
    Observable への回帰リスクで見送り) + iframe contentWindow (範囲外)。

- **html/dom ARIA reflection (属性 + 要素参照) + window グローバル公開** (bridge + Dommy)。
  - **ARIA 要素参照 reflection** (Dommy): aria-element-reflection 0→8/27、disconnected 1/2。単数
    `aria<Xxx>Element`→"aria-xxx" (Element or null)、複数 `aria<Xxx>Elements`→"aria-xxx" (Element 配列)。
    `@aria_element_refs`/`@aria_elements_refs` に explicit ref を保持 (set で content 属性を ""、getter は
    explicit を優先)、IDREF は要素の **root subtree** で解決 (切断時も有効)、set/removeAttribute の
    `aria-*` 直接書き込みで explicit ref をクリア。**named element access**: ハーネスで `document.
    querySelectorAll("[id]")` を globalThis に mirror (既存グローバルは shadow しない) し、裸の id 参照を解決。
    残り 19 は shadow-DOM のアクセシビリティスコープ検証 (explicit ref が深い shadow で null になる)、
    labelledby は `test_driver.get_computed_label` (a11y ツリー計算) で範囲外。
  - **ARIA / role reflection** (Dommy): **aria-attribute-reflection 0→41/41 + tentative 0→3/3 green**。
    `Element#aria_content_attr` が `ariaXxx`→"aria-"+xxx.downcase、`role`→"role" にマップ。get は
    nullable DOMString (absent→nil/null)、set は null/undefined→属性削除・それ以外→ToString。__js_get__/
    __js_set__ の else に汎用ハンドラを追加。
  - **ブリッジ一般バグ修正** (bridge): JS `undefined` の **プロパティ set 値** が `dehydrate`
    (tagged でない) 経由で Ruby に gem の **`:undefined` シンボル**として渡り、Bridge::UNDEFINED と
    別物になっていた (args 経路 `dehydrateArgs` は `{__rb_undefined}` でタグ付け→正しく Bridge::UNDEFINED)。
    `unwrap` の case に `when :undefined → Bridge::UNDEFINED` を追加し正規化。これで `el.ariaLabel =
    undefined` 等の nullable setter が undefined を null と同様に扱える。
  - **window に JS 組み込みを公開**: `install_browser_globals` で String/Number/Boolean/Object/Array/
    Math/JSON/… を `window[name] = globalThis[name]` で window プロキシに own プロパティとして付与。
    window は global object なので browser-correct。
  - **`accessKeyLabel`**: `accesskey` 属性が単一の 1-code-point トークンなら `Alt+<KEY>`、
    空/複数/複数文字なら "" (access-key-label 2/2 green)。
  - **reflection-*.html は意図的に未 vendor**: ブリッジは全 DOM 操作が Ruby 往復で、reflection.js の
    数千の属性×要素テストは 1 ファイルで 60s VM タイムアウト超過。物量 × overhead が原因で実用不可。
    残る historical の失敗は permissive な window `has` トラップ (`'HTMLTableDataCellElement' in window`
    が常に true)、未知 HTML 要素が `Dommy::Element` 止まりで HTMLUnknownElement 化されない、parser/all/
    applet 等の obsolete 機能 — いずれも構造的・範囲外。

- **MutationObserver 配信を native microtask キューに統合 + MO 改善** (bridge + Dommy)。
  - **タイミング修正 (核心)**: dommy の `scheduler.queue_microtask` (MO 配信等) は Ruby 側の `@microtasks`
    キューに積まれ、native QuickJS の promise ジョブキューとは別ドレインだった。そのため
    `el.textContent="foo"; await Promise.resolve()` でテストが期待する「await 後に配信済み」が成立せず、
    複数の変更が1コールバックに集約 (「1レコード期待だが3」) されていた。**`Scheduler#native_microtask_scheduler`
    フック**を追加し、ブリッジが `schedule_native_microtask` → `__rbHost.scheduleMicrotask(id)` →
    `Promise.resolve().then(() => __rb_run_microtask(id))` で Ruby proc を native ジョブとして enqueue する
    よう配線 (`HostBridge#window=` で注入)。これで host-side microtask が JS の await/Promise reaction と
    FIFO に並び、textContent 1→3。vanilla CRuby ではフック未設定で従来通り `@microtasks` にフォールバック。
  - **childList レコードの type フィルタ** (実バグ): `notify_child_list_mutation` が observer の登録
    `child_list` フラグを見ずに全 observer へ配信していた (attribute/characterData は確認済みだった)。
    `find_matching_entry` で `entry[:child_list]` を確認 → `observe(t, {childList:false, attributes:true})`
    が childList レコードを受け取らなくなった (attributes 40→41)。
  - **observe を target の document に登録** (実バグ): MutationObserver は `@document = window.document`
    (メイン) 固定で、別 document (DOMParser 製 XML doc) の要素を observe しても、その doc の coordinator に
    登録されず変更が届かなかった。target の node-document に登録 (`@registered_docs` で追跡し disconnect で
    全解除) → textContent CDATA (XML-doc MO) が通り textContent 1→4 green。
  - **callback の `this`=observer**: `invokeCallback`/`invoke_callback` に thisArg、HostCallback に
    `__js_call_with_this__`、MutationObserver が observer を receiver に呼ぶ (callback-arguments green)。
  - **`truthy_option` を JS ToBoolean に**: MutationObserverInit メンバは WebIDL boolean なので
    `attributes: ["abc"]` (オブジェクト) も truthy (sanity green)。
  - 残りの MO 失敗はタイミングではなく個別の backend 限界: libxml2 が fragment/normalize の隣接テキストを
    merge (addedNodes 不一致)、Range.deleteContents/extractContents が characterData レコードを発火しない
    (かつ setup の隣接テキストも merge)、unprefixed-ns 属性 (removeAttributeNS) が libxml2 で round-trip
    しない、parser 観測 (ストリーミングパーサ無し)、replaceChild(self,self) の 2レコードセマンティクス。

- **dom/lists (DOMTokenList) 完全対応** (Dommy + bridge)。**46→189/189 (100%)、全 5 ファイル green**。
  - **反映 DOMTokenList 属性**: `ClassList` を任意の content attribute に一般化 (`@attribute`)。
    `Element#reflected_token_list` が要素+名前空間に応じて DOMTokenList か **UNDEFINED**（→ JS undefined）
    を返す: relList = a/area/link(HTML) + a(SVG); htmlFor = output(HTML); sandbox = iframe(HTML);
    sizes = link(HTML); 非該当は undefined（null でなく）。`output.htmlFor`/`iframe.sandbox`/`link.sizes`
    はサブクラスの reflect_string を JS 読み取りで token list にインターセプト（Ruby の文字列 accessor は維持）。
  - **iterable メソッド = Array.prototype 由来**: WebIDL の value-iterator interface（indexed getter +
    `iterable<>`）は keys/values/entries/forEach/@@iterator が **%Array.prototype% の関数そのもの**
    （`list.values === Array.prototype.values`）。bridge のカスタムイテレータを Array.prototype のメソッド
    に置換（proxy は array-like なので動作し、Array Iterator を返すので `instanceof Array` は false）。
    forEach も追加。
  - **getElementsByTagNameNS** を Element/Document に追加。

- **dom/collections (WebIDL legacy platform object 反映) 実装** (bridge JS + Dommy)。**12→50/53
  (94.3%)、8 ファイル green**。HTMLCollection / DOMStringMap (dataset) / NamedNodeMap の indexed +
  named プロパティを Proxy トラップで spec 通りに反映:
  - **named プロパティ**: Ruby 側が `__js_named_props__` で live な supported property names を公開
    (HTMLCollection = 各要素の id→name を tree 順・重複除去・name は HTML 名前空間のみ; DOMStringMap =
    camelCase した `data-*` キー; NamedNodeMap = 属性の qualified name)。bridge は `__rb_named_props` で
    毎回ライブ取得し、`ownKeys`/`getOwnPropertyDescriptor`/`has`/`set`/`defineProperty`/`deleteProperty`
    に反映。named は HTMLCollection/NamedNodeMap で**非列挙・読取専用**、DOMStringMap で**列挙可・書込可
    + named deleter** (`__js_delete__`)。
  - **legacy platform [[Set]]/[[Delete]]**: 配列インデックス代入は expando にならず no-op(sloppy)
    /TypeError(strict); 読取専用 named プロパティへの代入も拒否（既に expando が shadow している場合のみ更新）。
  - **インデックス descriptor は writable:false**; 範囲外の配列インデックスは **undefined**（named に
    フォールバックしない — `coll[2147483648]` は undefined だが `namedItem(2147483648)` は要素）。
  - HTMLCollection は **@@iterator のみ**（`iterable<>` 宣言なし → values/keys/entries/forEach を持たない）。
  - **Dommy 修正**: `getElementsByTagNameNS` を Element/Document に追加; `namedItem` の数値引数が
    int32 超で Float として渡る件を整数文字列化; HTMLCollection の数値文字列アクセスを配列インデックス
    (item) と非インデックス (named) で分岐。`StandaloneEventTarget` 同様の名前付き collection マッピング。

- **dom/observable (WICG Observable API) 新規実装** (bridge JS + Dommy)。**0→187/241 (77.6%)、10
  ファイル green**。QuickJS は本物の JS エンジンなので、Observable はリアクティブプリミティブを

- **dom/observable (WICG Observable API) 新規実装** (bridge JS + Dommy)。**0→187/241 (77.6%)、10
  ファイル green**。QuickJS は本物の JS エンジンなので、Observable はリアクティブプリミティブを
  **JS ポリフィル** (`lib/dommy/js/observable_runtime.js`) として実装し、DOM プロトタイプ seed 後に
  `install!` で eval。host 連携点は EventTarget / AbortController / グローバルエラー報告のみ。
  - **`Observable`/`Subscriber`**: subscribe コールバック、`next/error/complete/addTeardown/active/signal`
    (#private フィールドで receiver-less 呼び出し→TypeError)、ACCEPT 完了/error で signal abort→teardown
    LIFO。**report exception** は `error` ErrorEvent をグローバルに dispatch (Error は stack から
    lineno/colno、文字列等は 0)。
  - **operators**: map/filter/take/drop/flatMap/switchMap/takeUntil/catch/finally/inspect (Observable 返し) +
    first/last/find/some/every/reduce/toArray/forEach (Promise 返し)。take/drop の負値は unsigned long long
    として最大値 (Infinity) に。first/last は空完了で RangeError。takeUntil は notifier の next **も error も**
    complete を呼ぶ (error 非伝播)、sync 発火時は source を購読しない。
  - **`Observable.from`**: Observable/async-iterable/iterable/Promise。TC39 GetMethod 準拠 (present-but-not-
    callable は TypeError、@@iterator は from() 時と subscribe 時に**再読**しキャッシュしない)。
  - **`EventTarget.prototype.when`**: `addEventListener(type, …, {signal})` を購読/購読解除に橋渡し。
    `new EventTarget()` (StandaloneEventTarget) が "EventTarget" として crossing するよう NAME_OVERRIDES 追加。
  - **基盤バグ修正 (Dommy、全領域に有益)**: (1) **`queueMicrotask`** が window scheduler 経由で native
    promise キューと別だったため Promise reaction と FIFO 順序がずれていた → `Promise.resolve().then` に。
    (2) **`setTimeout`/`setInterval` の delay** が undefined/非数値で `to_i` クラッシュ → 0 に強制。
    (3) **`AbortSignal` の abort 理由**が無指定/undefined で `null` だった → spec 通り **AbortError
    DOMException** を既定に。(4) **`AbortSignal`** をグローバル公開 (static `abort`/`any`/`timeout`)。
  - 残り 54: 連鎖タイマー依存の async-iterable (harness pump 制約)、detached-document (.window.js)、
    高度な teardown/abort 順序、microtask タイミング細部。

- **dom/traversal (TreeWalker / NodeIterator) 代表コーパス + 掘り下げ修正** (Dommy + bridge)。
  **1568/1584 (99.0%)、8 ファイル green**。修正した実バグ:
  - **`invoke_filter` が JS フィルタを呼べていなかった**: 関数フィルタ (HostCallback) も
    `{acceptNode}` オブジェクト (Hash) も Ruby の `accept_node`/`call` に respond せず**常に
    FILTER_ACCEPT** を返していた。`__js_call__("call", …)` 経由で呼び、戻り値を WebIDL 強制
    (boolean→0/1)。acceptNode が callable でなければ TypeError。
  - **TreeWalker の SKIP/REJECT セマンティクス**: `traverse_children`/`traverse_siblings`/`next_node`/
    `previous_node` を WHATWG アルゴリズムに書き換え (SKIP=子へ降りる、REJECT=サブツリーごと
    スキップ)。previousNode はルートも返しうる (parentNode と非対称)。
  - **NodeIterator の commit セマンティクス**: `next_node`/`previous_node` を**ローカル変数**で
    走査し、**ACCEPT 時のみ** referenceNode/pointerBeforeReferenceNode をコミット (null を返す際は
    位置を変えない)。これが NodeIterator.html を 118→757 に押し上げた決定打。
  - **`NodeIterator` pre-removing steps**: live iterator を Document に登録し、`remove_node_with_notify`
    の unlink 前に各 iterator の referenceNode を WHATWG 手順で調整。NodeIterator-removal 5→15/16。
  - **`hasChildNodes()` / `hasAttributes()` の欠落**: Element/Document/Fragment/ProcessingInstruction/
    DocumentType/CharacterData に未実装で、common.js の `previousNode`/`nextNode` ヘルパーが
    `node.hasChildNodes()` で**"not a function"** を投げていた。全ノード型に追加。
  - **`NodeFilter.bitmask_for` を `1 << (nodeType-1)` に**: PI/CDATASection/Attr を扱えず PI ルートの
    iterator が空になっていた。
  - **whatToShow / currentNode の強制**: `createTreeWalker`/`createNodeIterator` で undefined→既定
    0xFFFFFFFF・null→0・それ以外 ToUint32。currentNode setter は非 Node に TypeError (`is_a?(Node)`)。
  - bridge: `NodeFilter` 定数を `INTERFACE_CONSTANTS` で公開、`NodeFilter`/`TreeWalker`/`NodeIterator`
    を BASE_CHAINS に seed。残り 16 件は assert_readonly (Proxy descriptor ギャップ)、フィルタ例外の
    同一性、再入 InvalidStateError で構造的・範囲外。

- **Range (`dom/ranges/`) 代表サブセット + 掘り下げ修正** (Dommy)。**310/319** (7 ファイル中 3 green;
  計測した全 dom/ranges は 20524/23304 = 88.1%)。3 つの実バグ: (1) **`Document.createCDATASection`**
  追加 (`CDATASectionNode` = Text サブタイプ nodeType 4 + Backend.create_cdata/cdata_class +
  wrapper マッピング)。common.js の `setupRangeTests()` がこれ無しで死亡し全 Range テストが setup で
  error していた。(2) **CharacterDataNode に `ownerDocument`** (テキストノードが null を返し
  `rangeFromEndpoints` の createRange が全滅)。(3) **`Range#comparePoint`/`isPointInRange` 実装 +
  `compareBoundaryPoints` の検証**: offset は WebIDL unsigned long (負値 wrap → IndexSizeError)、
  無効 `how`→NotSupportedError、別ツリー→WrongDocumentError、doctype→InvalidNodeTypeError。
  巨大な組み合わせテスト (compareBoundaryPoints 9313 / comparePoint 5580 / isPointInRange 5733 /
  intersectsNode 2356) は Range がコーパスを支配するため vendor せず (実装は保持)。content 操作
  (deleteContents/extractContents/insertNode/surroundContents/cloneContents) は srcless iframe を
  2 つ作り両方で操作して比較するパターンで範囲外。
- **MutationObserver の record 詳細** (Dommy)。**98→109/133** (childList 19→28、attributes
  38→40)。(1) **ノード移動 = removal + addition** (`detach_with_notify`): insertBefore/appendChild/
  append/prepend で既存ノード (親あり) を挿入する際、旧親へ childList removal レコードを先に発火
  (within-parent の並べ替えは同一親に 2 レコード)。(2) **削除前の sibling 捕捉**
  (`Document#remove_node_with_notify`): 全 remove 経路 (Element/CharacterData の `remove`、
  `remove_child`、Range `delete_contents`) が unlink 前に previous/next sibling を**ラップして**
  捕捉し record に渡す (コーディネータは明示 sibling を verbatim 記録するので raw Nokogiri ノードだと
  undefined になっていた)。(3) **attributeNamespace** をレコードに記録 (setAttributeNS/
  removeAttributeNS が `namespace:` を渡す; namespaced 属性は局所名を小文字化しない)。残り: Range
  "child and data removal"・`Node.normalize`・fragment-text は **libxml2 の隣接テキスト結合**で
  ブロック (テスト設定が 3 つの別テキストノードを作るが 1 つに融合) — バックエンド根本制約。
  callback の `this`=observer はブリッジのコールバック receiver 対応が要るため見送り (1 件)。
- **History API (pushState/replaceState) 自己完結サブセット** (Dommy)。
  `the-history-interface` の自己完結テスト **7/7 green** (pushState/replaceState の基本・引数省略・
  state・cross-origin SecurityError)。`History#push`/`replace` が URL を文書 URL に対して解決し、
  parse 失敗 or **cross-origin なら SecurityError** を投げる (`resolve_url!`)。history/location の
  WPT は大半が navigation (back/forward/popstate)・実 iframe・cross-origin 依存で、no-network・単一
  文書の Dommy では本質的に動かせないため、それらは vendor しない (url_rewriting は iframe 生成 +
  blob URL + origin ルール、numbered 001-012 は実ナビゲーション)。
- **MutationObserver 取り込み** (ハーネス + Dommy)。**17→98/133**、5 ファイル green (disconnect /
  inner-outer / takeRecords / + attributes/characterData/sanity が大幅前進)。(1) **ハーネスの強制
  timeout** (最大レバー、再利用可能): 配信されないミューテーション (Range 操作など) で async_test が
  1つでもハングすると testharness の completion が発火せず**そのファイルの全結果が失われていた**
  (childList/attributes/characterData/textContent が 0/0)。`WptHarness#run` が pump 後に
  `__wptResults === null` なら決定論クロックを 11s×2 進め、testharness の harness-timeout (10s,
  `setTimeout(()=>tests.timeout())`) を発火させて未完了テストを TIMEOUT 扱いにし completion を回す。
  → 4 ファイルが 0/0 から復活。(2) **CharacterData メソッド** (Dommy): `Text`/`Comment` に
  `appendData`/`insertData`/`deleteData`/`replaceData`/`substringData`/`length` を実装 (各変更は
  `write_data` 経由で characterData レコードを発火、offset 範囲外は IndexSizeError)。(3) **observe()
  検証** (Dommy): `attributes`/`characterData` の暗黙 true は companion (attributeOldValue/Filter/
  characterDataOldValue) が**あり、かつメンバー省略時のみ**。明示 false + companion は `Bridge::TypeError`、
  3 種いずれも無しも TypeError (JS TypeError にマーシャル)。(4) **コールバック引数**: `(records,
  observer)` を渡す。残り: Range 操作のレコード未配信 (timeout)、record の nextSibling/addedNodes 詳細、
  `Node.normalize`、パーサ挿入の document 監視、複数 observer の textContent 累積タイミング。
- **Selectors (querySelector/matches/closest) 取り込み** (ハーネス + ブリッジ + Dommy)。
  Element-matches **0→522/672**、ParentNode-querySelector-All **0→1505/1977**、Element-closest
  **24→28/29**、querySelector-scope **0→4/4** (dom 2200→4262)。(1) **動的 iframe 読込**
  (ハーネス、最大レバー): 包括スイートは `document.createElement("iframe")` + `frame.src=` +
  `frame.onload=` で実行時に iframe を生成し、その contentDocument に対して全テストを定義する。
  `WptRunner` が inline script の `.src="…\.html"` 代入を検出し content を vendor (フラグメント除去
  キー)、`BrowserHarness#wire_dynamic_iframes` が pump 各ラウンドで未配線 iframe を
  `Dommy.parse` → contentDocument 設定 → `expose_constructors_on` → `load` イベント発火
  (Dommy は `iframe.onload=` を load で呼ぶ) → `init()` が走り ~1900 subtests 解錠。
  (2) **`:scope`** (Dommy): `ScopedCSSPseudoHandlers` で Nokogiri の `nokogiri:scope(.)` を
  コンテキスト要素に解決。Nokogiri は `el.css` を子孫 (`.//`) に限定し要素自身を含めないため、
  `:scope` 含有クエリは文書から評価して el の子孫に絞る。(3) **closest 書き直し** (Dommy):
  scope ハンドラでセレクタ評価 → 最近接の inclusive ancestor を返す。(4) **無効セレクタ →
  SyntaxError** (Dommy): Nokogiri の CSS *パース* エラー ("unexpected … after …") は
  SyntaxError、"Unregistered function" (未対応疑似 `:hover` 等) は空マッチに degrade。
  (5) **`DocumentFragment.ownerDocument`** (Dommy): null だったのを所有文書に (interface チェックの
  `ownerDocument.defaultView.NodeList` が解決)。(6) **`NodeList`/`HTMLCollection` を BASE_CHAINS に**
  (ブリッジ): `result instanceof NodeList` 用にグローバルコンストラクタをシード。残りの大半は
  **Nokogiri の CSS パーサが多くの CSS3 セレクタを解析できない**根本制約 (別エンジンが必要)、
  および未対応疑似・名前空間・case-insensitive 属性フラグ。
- **DOM Parsing & Serialization (`/domparsing/`) 取り込み** (ブリッジ + Dommy)。**29→68/100**、
  5 ファイル green (insert-adjacent / innerhtml-06 / innerhtml-li-autoclosing / outerhtml-01 /
  domparser-spurious-attributes)。(1) **insertAdjacentHTML** (Dommy): 位置文字列を ASCII
  case-insensitive に (`beforeBegin` 等が no-op していた — 6→30/31)、`add_previous_sibling` は
  forward 反復で順序保持 (afterend のみ reverse)、無効位置→SyntaxError、親なし/親が Document の
  beforebegin/afterend→NoModificationAllowedError。(2) **set 経路を `dom_guard` で包む** (ブリッジ):
  `__rb_host_set` が DOMException を投げる setter (例 `documentElement.outerHTML=` →
  NoModificationAllowedError) でタグ付き例外を返し、JS set トラップが re-throw — 従来は生 Ruby
  例外が漏れていた潜在バグ。(3) **outerHTML setter** (Dommy): `Element#__js_set__` に `outerHTML`
  を配線 (従来未処理 = expando 化していた)。(4) **[LegacyNullToEmptyString] ToString** (ブリッジ):
  set トラップが innerHTML/outerHTML を JS 側で null→""、他は `String(value)` 強制 (`= 42` /
  `{toString}` / throwing toString が正しく; innerhtml-07・outerhtml-02 完全グリーン)。
  (5) **`compatMode`** (Dommy): doctype 有無で BackCompat/CSS1Compat。(6) **DOMParser の無効 enum**:
  `Bridge::TypeError` (WebIDL enum)。(7) **XML パース/直列化** (Dommy): `Backend.parse_xml` (Nokogiri
  XML パーサ) で `parseFromString(…, "text/xml")` が正しい XML 文書に、`document_element` を
  `at_css("html")` から `nokogiri_doc.root` に (XML 文書の root を返す)、`XMLSerializer` を `to_xml`
  ベースに (自己閉じ + XML エスケープ)。dommy 側テスト 3 件を spec 準拠に更新 (DOMParser enum →
  TypeError、insertAdjacentHTML 親なし → throw)。残り: XMLSerializer の WHATWG 名前空間
  シリアライズアルゴリズム (25、Nokogiri の to_xml は名前空間 prefix 管理が WHATWG と不一致)、
  style 属性の CSS 直列化 (4)、Nokogiri が隣接テキストを結合する件 (insert_adjacent_html /
  innerhtml-04 各 1)。
- **Encoding (`/encoding/`) 取り込み + 型付き配列マーシャリング** (ブリッジ + Dommy)。encoding
  **4→118/178**、5 ファイル green (api-basics / api-surrogates-utf8 / textdecoder-fatal /
  textdecoder-ignorebom / textencoder-utf16-surrogates)。(1) **型付き配列マーシャリング層**: JS の
  ArrayBuffer / TypedArray は `dehydrate` で `{__rb_bytes:[…]}` に (従来は Object.keys で
  index→値の Hash になり "no implicit conversion of Array into Integer")、Ruby 側は
  `Bridge::Bytes`(< Array) に。逆向きは host が `Bytes` を返すと `rehydrate` が `new Uint8Array`
  に。`TextEncoder#encode` が Uint8Array を返すように。(2) **WHATWG UTF-8 デコーダ** (Dommy
  `text_codec.rb`): バイト単位のステートマシン (bytesNeeded/lower-upper boundary) で streaming
  (`{stream:true}` 跨ぎの state)、正確な U+FFFD 配置 (`[0xF0,0x9F,0x41]`→"�A" 等)、
  `fatal`→TypeError、EOF flush (不完全列は 1 個の U+FFFD)、BOM ストリップ/ignoreBOM を実装。
  `fatal`/`ignoreBOM` 属性も公開。(3) **`encodeInto`** (ブリッジ JS 側): TextEncoder プロトタイプ
  に定義し destination Uint8Array を in-place 変更 (host 往復ではコピーになるため)。スカラー値を
  UTF-8 に、入りきらない code point の手前で停止、`{read, written}` を返す。(4) **単独サロゲートの
  スクラブ** (ブリッジ): `dehydrate` が JS 文字列の unpaired surrogate を U+FFFD に置換 (Ruby 文字列は
  lone surrogate を保持できないため、spec の USVString 変換と等価)。残り ~60 は ASCII/UTF-8 スコープ外
  (SharedArrayBuffer は WebAssembly.Memory 依存・54 件、Big5、ArrayBuffer detach)。
- **C: ライブコレクション / イテレータ** (ブリッジ + Dommy)。`urlsearchparams-foreach`
  **2→6/6 (green)**、`Node-childNodes` **2→4/6**、`Element-getElementsByClassName` **1→2/3**。
  (1) **array-like proxy の own-index 反映** (ブリッジ): `makeHandler` に `getOwnPropertyDescriptor`
  / `ownKeys` / `has` トラップを追加し、`ARRAY_LIKE_COLLECTIONS` (NodeList/HTMLCollection/…) の
  インデックス 0..length-1 を own enumerable configurable プロパティとして公開 (length はライブに
  ホストへ問い合わせ)。testharness の `assert_array_equals` が `hasOwnProperty(i)` で要素の有無を
  見るため必須。`2 in nodeList` も範囲外で false に。(2) **childNodes をキャッシュ済みライブ
  NodeList に** (Dommy): Element は既に `@live_child_nodes`、Fragment / Document も同様に
  キャッシュ (`fragment.childNodes === fragment.childNodes` + ミューテーション反映)。
  `LiveNodeList#__js_get__` の範囲外インデックス→`UNDEFINED`。(3) **本物のイテレータ** (ブリッジ):
  array-like プロトタイプに keys/values/entries/Symbol.iterator を JS 側で定義 (Ruby メソッドから
  外す) → `list.keys() instanceof Array` が false、length/[i] をライブに読む。URLSearchParams の
  Symbol.iterator は各 `.next()` で `entries()` を再読込するライブ版に (`for…of` 中の delete/
  search 変更が見える)。**残り**: childNodes のテキストノード識別 (Nokogiri が `add_child` で
  テキストノードを再生成 → wrapper の backend 参照が古くなる) と new Document() のクロスドキュメント
  identity — 深い wrapper-cache の課題で別途。
- **B: WebIDL イベント引数 / 辞書変換** (ブリッジ + Dommy)。`Event-constructors` **8→14**、
  `Event-initEvent` **9→12**、`CustomEvent` **2→3**、`AddEventListenerOptions-once` **3→4**
  (4 ファイル green)。(1) **コンストラクタ引数の WebIDL 強制** (ブリッジ `coerceConstructorArgs`):
  `CONSTRUCTOR_DICTS` (Event/CustomEvent の宣言メンバー + 型) を持ち、`constructInterface` で
  type を `String()` 強制 (throwing toString が伝播、引数なしは TypeError)、init は宣言メンバー
  のみを宣言順で読む (stray getter を呼ばない、null バイト入りキー `"bubbles\0…"` も読まない、
  boolean は JS truthiness)。完全に Ruby 側へ渡る前に正規化するので `is_a?(Hash)` 等の既存挙動を
  壊さない。(2) **イベントの未知プロパティ→undefined** (Dommy): `Event#__js_get__` の `else` が
  `Bridge::UNDEFINED` を返す (`ev.sweet` は undefined、`target`/`srcElement`/`currentTarget` 等の
  真に null な属性は明示 case で nil)。(3) **initEvent** (Dommy): dispatch 中は no-op (dispatch
  フラグ)、type 引数必須、`initCustomEvent` を追加。(4) **once は呼び出し前に除去** (Dommy): ネスト
  dispatch で二重発火しない。(5) **`new Document()` 構築可能化** (Dommy): 空の application/xml 文書。
  残り: capture の dummy-getter (addEventListener options は host_call 経路で辞書変換が未適用) と
  GC 圧力下のコールバック ID 再利用、Event-isTrusted の記述子検査、bubbles の cloneNode。
- **イベント伝播フラグ + capture オプション** (Dommy)。`Event-propagation.html` **4→7/7**、
  `EventListenerOptions-capture.html` **0→2/4**。(1) dispatch 末尾で stop-propagation /
  stop-immediate フラグをクリア (canceled フラグは保持) — 同じ Event を再 dispatch できる
  ように。dispatch 前に立てた `stopPropagation()` は引き続き尊重。(2) `deliver_at` が配信
  *前* にもフラグ確認 (祖先が無い AT_TARGET だけのケースでも pre-set フラグを尊重)。
  (3) capture フラグを **JS truthiness** で判定 (`EventTarget.js_truthy?` / `.capture_flag`):
  Ruby では `0`/`""` が truthy だが JS では falsy、`Bridge::UNDEFINED` センチネルも falsy。
  `{capture:0}`/`undefined` third-arg を正しく非 capture に。(4) `remove_event_listener` が
  `options` を取り (callback, capture) でマッチ (旧実装は callback だけで全削除) — 全
  ディスパッチ箇所が `args[2]` を渡す。残り 2 (capture): dummy getter を読まない遅延 dict
  変換 (Event-constructors と同根) と、GC 圧力下のコールバック ID 再利用による stale
  capture リスナー (深いブリッジのライフサイクル問題)。
- **createElement の文書型対応** (Dommy + ハーネス)。`Document-createElement.html`
  **59→123/147**。createElement は HTML 文書のみ ASCII 小文字化し、HTML 名前空間
  (HTML/XHTML 文書) か null 名前空間 (非 XHTML の XML 文書) を付与。`Element#tagName` は
  「HTML 名前空間 **かつ** HTML 文書」のときだけ ASCII 大文字化 (XHTML 要素 = HTML 名前空間
  だが XML 文書 → 大文字化しない)。`Document#html_document?` (content_type == "text/html")
  を追加。`create_element` は名前空間メタデータを `__internal_set_namespace__` で保持し
  localName/tagName/namespaceURI が一貫。ハーネス側: iframe の XML/XHTML 文書に
  `content_type` を設定し (`text/xml` / `application/xhtml+xml`)、各 iframe に**専用の Window**
  (`Dommy.parse` 産) を defaultView として与え、`Runtime#expose_constructors_on` で seed 済み
  constructor を sub window proxy にも公開 (cross-window `instanceof` / `contentWindow.document`
  が正しい sub 文書を返す)。ブリッジは sub window proxy を JS グローバル配列で保持し GC で
  ハンドルが失われないようにする。残り ~24 は古い緩いケース (`f}oo`/先頭結合文字/`￿` —
  XML Name production 的に無効で実ブラウザ/jsdom も落ちる、追わない)。
- **classList を順序付き集合に** (Dommy)。`Element-classlist.html` **1235→1420/1420 (完全
  グリーン)**。DOMTokenList の token set を「class 属性を ASCII 空白で分割し重複排除した
  順序集合」に (`class_tokens` に `.uniq`) — length/item/iteration/contains が集合を見る
  (`value`/`toString` は属性の生値)。indexed getter `classList[i]` は範囲外/負で `undefined`
  (`item(i)` メソッドは null) を `Bridge::UNDEFINED` で返す。`update_tokens` は add/remove/
  replace で**常に**集合を再シリアライズ (重複 collapse + 空白正規化) — 唯一の例外は「空集合
  かつ属性が存在しない」で属性を作らない (空集合だが属性が在れば `""` を設定、削除しない)。
  `toggle(token, force)` は force 一致の no-op では更新せず属性を不変に。`replace` の検証順を
  spec 準拠に (両引数の空チェック→SyntaxError が両引数の空白チェック→InvalidCharacterError
  より先、`replace(" ", "")` は SyntaxError)。dommy 側テスト 1 件を spec 準拠に更新
  (最後のトークン削除は属性を `""` にする、削除しない)。
- **`url-constructor` / `url-origin` のデータ供給を解消** (ハーネス + ブリッジ + Dommy)。
  両ファイルは `fetch(urltestdata.json).json()` でコーパスを流し込み 1 つの `promise_test` で
  ~1290 ケースを回すが、ずっと 0/1 だった。原因は 3 段の連鎖:
  1. **testharness の DOM 出力が NUL でクラッシュ** (ハーネス)。完了時に testharness が各
     subtest 名を `document.createTextNode` で DOM に描画するが、URL ケースのテスト名には
     入力の NUL/制御文字がそのまま入る。libxml2 バックエンドの Text ノードは NUL を拒否
     (`ArgumentError: string contains null byte`) → 完了処理ごと落ちてそのファイルの結果が
     0 件になっていた。結果は `add_completion_callback` でプログラム的に回収しているので、
     `WptHarness` 初期化で **`setup({ output: false })`** を呼び testharness の視覚出力を無効化。
  2. **`Response#json` が lone surrogate を拒否** (Dommy `fetch.rb`)。`urltestdata-javascript-
     only.json` は `\uD800` 等の単独サロゲートを含み、Ruby の `JSON.parse` が "invalid
     surrogate pair" で例外 → `Promise.all` が reject → メイン 998 ケースが 1 件も走らない。
     `scrub_lone_surrogates` を追加し、単独サロゲートのエスケープを U+FFFD に置換してから
     parse (有効なペアはそのまま保持)。これは URL パーサが行う置換と等価で spec 準拠。
  3. **URL コンストラクタが TypeError でなく DOMException を投げていた** (Dommy + ブリッジ)。
     WHATWG では `new URL(bad)` / `url.href=bad` は **`TypeError`** を投げるが、Dommy は
     `DOMException::SyntaxError` を投げ、`assert_throws_js(TypeError, …)` (instanceof 検査) が
     275/276 件で失敗。`Dommy::Bridge::TypeError` (専用例外、bare な Ruby `TypeError` とは別物
     なので本物の型バグをマスクしない) を新設し、URL の constructor/href= がこれを投げる
     (`URL.parse`/`canParse`/`blob_inner_origin` の rescue も追従)。ブリッジは `dom_guard` で
     これを捕捉し `{name:"TypeError", js_native:true}` でタグ付け → `makeHostError` が
     `info.js_native` のとき本物の JS コンストラクタ (`new globalThis[name](msg)`) で再生成。
  あわせて: blob URL の origin を内側スキームが http/https/file のときだけ内側 origin に
  (それ以外は opaque origin) — `blob:ftp://`/`blob:ws://`/`blob:blob:https://` 系の 4 件。
  URLSearchParams が **owner-backed (URL の query から初期化) のときは先頭 `?` を除去しない**
  (`??a=b` の query "?a=b" は先頭 `?` がデータで最初の名前が "?a") — 1 件。
  → url-constructor **0/1→888/888**、url-origin **0/1→401/401**、url **89.0%→99.3%**、
  **total 83.6%→89.3% (3317/3714)**、19 ファイル green。dom は不変。
- **イベント伝播の WHATWG 準拠化 + Event 定数** (Dommy + ブリッジ)。`dom/events` を
  取り込み 22→34/57。(1) `dispatch_event` を capturing→at-target→bubbling の3フェーズに
  書き直し: 祖先パスを常に構築 (非 bubbling でも capture フェーズあり)、`eventPhase`
  (NONE/CAPTURING/AT_TARGET/BUBBLING) を明示設定、capture リスナーは capturing 相、
  非 capture は bubbling 相 (target では両方)、`stopPropagation` は `catch(:stop_…)` で
  打ち切り。リスナー dedup を (listener, **capture**) に修正し、`addEventListener` の
  3 引数 boolean / `{capture:}` を解釈。`EventTarget` に `__internal_event_parent__` の
  既定 (nil) を追加し、`send`→`__send__` で XHR 等の `send` オーバーライドとの衝突を回避。
  (2) **Event 定数** (`Event.CAPTURING_PHASE` 等) をブリッジの `INTERFACE_CONSTANTS` で
  Event の interface オブジェクト+prototype に公開 (Node 定数と同機構)。(3) `Event#
  returnValue` (= !defaultPrevented、setter で cancel) と `Event#isTrusted` (false) を追加。
- **Node.isEqualNode + DOMImplementation 一式** (Dommy)。
  `Node-isEqualNode.html` **0→9/9 (完全グリーン)**。`Internal::NodeEquality` が WHATWG の
  "equals" (型別データ + 順序付き子孫の再帰比較) を実装し、`Node` モジュールの
  `is_equal_node` から全ノードクラス (Element / CharacterData→Text・Comment / Fragment /
  Document / DocumentType / ProcessingInstruction) に配線。比較はラッパーの公開アクセサ
  経由 (`__js_get__` の型別プロパティ + `child_nodes` + `attributes`) なので不均一なノード
  クラス間で一様。あわせて: `DocumentType` に publicId/systemId; `document.implementation`
  (`DOMImplementation`) の `createDocumentType` / `createDocument` (独立 XML 文書、任意で
  document element) / `createHTMLDocument` (doctype + html>head,body); `ProcessingInstruction`
  + `document.createProcessingInstruction`; `Document#appendChild` (ドキュメント直下への
  ノード追加)。
- **ブリッジの undefined / null 区別** (ブリッジ + Dommy)。JS `undefined` と `null` が
  両方 Ruby `nil` に畳まれていたのを、トップレベルの呼び出し引数に限り区別:
  `dehydrateArgs` が明示的 `undefined` を `{__rb_undefined:true}` でタグ付け →
  `unwrap` が `Dommy::Bridge::UNDEFINED` センチネルに (`UNDEFINED` は symbol から
  `to_s`→"undefined" の object に。void 戻り値と同じセンチネルを双方向で再利用)。
  ネストした undefined (オプションバッグ等) は従来通り null のままで既存挙動を保護。
  消費側: `URL`/`URL.parse`/`canParse` の base `undefined`→base なし;
  `URLSearchParams#has`/`delete` の 2 番目 `undefined`→一引数形; `createElement(NS)` /
  `createAttribute(NS)` の WebIDL DOMString 強制変換 (`undefined`→"undefined"、
  `null`→"null"、namespace は nullable で `undefined`→null)。→ createElementNS
  **486→534/596**、url-statics-parse/canparse と urlsearchparams-delete/has が完全
  グリーン (total →**83.8%**、14 ファイル green)。
- **createElementNS の名前空間 + Document#childNodes + Node 定数** (Dommy +
  ブリッジ)。`Document-createElementNS.html` **316→486/596** (dom 1666→1839、total
  →**81.4%**)。3 つの連鎖した修正:
  - **Node の数値定数** (ブリッジ): `Node.ELEMENT_NODE` 等を Node の interface
    オブジェクトと prototype に定義 (`host_runtime.js` の `NODE_CONSTANTS`)。インスタンス
    は proxy get の `prop in target` フォールバックで継承値に届く。`assert_equals(el.
    nodeType, Node.ELEMENT_NODE)` が通るように。
  - **`Document#childNodes`** (Dommy): nil を返していた → 全ノードの NodeList を返す。
    testharness の `format_value` が DOCUMENT で `childNodes.length` を読むため、これが
    無いと assert 記録 (`AssertRecord`→`format_value`) が例外を投げ、"cannot set
    property status of undefined" として全 success ケースを潰していた。
  - **createElementNS の名前空間メタデータ** (Dommy): 作成時に (namespace, prefix,
    localName, qualifiedName) を Element に保持 (`__internal_set_namespace__`)。
    `tagName`/`localName`/`prefix`/`namespaceURI` がこれを優先。tagName は HTML 名前空間
    のときだけ大文字化 (非 HTML/SVG は case 保持 — `createElementNS(SVG,"svg").tagName`
    は "svg")。
- **classList (DOMTokenList) の void 戻り値ほか** (ブリッジ + Dommy)。
  `Element-classlist.html` **965→1235/1420**。`classList.add`/`remove` は
  `undefined` を返すべきだが Ruby `nil` が JS `null` にマーシャルされ全滅していた
  (260 件)。**`Dommy::Bridge::UNDEFINED` センチネル**を新設し (`__js_call__` が void op で
  返す)、ブリッジの `wrap` が `{__rb_undefined:true}` に、JS `rehydrate` が `undefined`
  に変換。あわせて `item(-1)` → `null` (負 index で Ruby が末尾要素を返していた)、
  `toString` を追加 (`String(classList)` が値を返す、stringifier)、トークンの `null`→
  `"null"` 強制変換 (`add(null)`/`contains(null)`)。
- **iframe `contentDocument` ロード** (ハーネス + Dommy)。createElementNS/
  createElement は各ケースを HTML / XML / XHTML の 3 document に対して走らせるが、
  XML/XHTML 変種は `<iframe src=/common/dummy.xml>` の `contentDocument` を使い、
  ハーネスが未対応で null → 全滅していた。`common/dummy.xml`・`dummy.xhtml` を vendor し、
  `WptRunner` が `<iframe src=…>` を検出して中身を読み (`iframe_docs`)、`BrowserHarness`
  が各 iframe を `Dommy.parse` でネスト文書に起こして `HTMLIFrameElement#
  __internal_set_content_document__` で配線 (defaultView は最上位 window なので
  `doc.defaultView.DOMException` も解決)。`HTMLIFrameElement#content_document` を
  settable 化。createElementNS の検証/生成ロジックは文書非依存なので、HTML 変種で通る
  ケースが XML/XHTML でもそのまま通る (XML 変種は全て非 HTML 名前空間 = 大文字化なし)。
  → createElementNS **106→316/596**、createElement **37→58/147** (dom 1165→1396、
  total →**62.7%**)。
- **createElement(NS) の検証を spec 準拠に** (Dommy)。`create_element_ns` は
  `Internal::Namespaces.validate_and_extract` を呼ばず独自の `NAME_RE` (コロン不可) で
  検証し名前空間抽出もしていなかった (prefixed 名・xml/xmlns 規則を全滅させていた)。
  `validate_and_extract` 使用に書き換え。さらに `Internal::Namespaces` の Name/QName を
  **canonical な `xml-name-validator` 相当の正規表現** (XML 1.0 NameStartChar/NameChar の
  Unicode 範囲) に置換し、`create_element` / `create_attribute` も `NAME` production で
  検証 (旧 `NAME_RE` は ASCII 限定で `İnput` 等を誤拒否)。→ createElementNS
  **72→106/596**、createElement **20→37/147** (dom 1113→1165)。残りは iframe variant +
  vendored コーパスの緩い旧ケース (`0:a`/`f:o:o` を valid 扱い) + null/undefined 強制変換。
- **window 上の interface コンストラクタ公開** (ブリッジ)。ブラウザでは window が
  グローバルオブジェクトそのものだが、ここでは window は別の host プロキシで、host
  get がこれらに `null` を返していた (`typeof null === "object"` で気付きにくい)。その
  ため `window.Node` / `document.defaultView.DOMException` 等が `null` になり、
  `assert_throws_dom(type, doc.defaultView.DOMException, …)` が `null.name` を読んで
  クラッシュ ("cannot read property 'name' of null")。`__rbHost.exposeConstructors
  OnWindow` を追加し (`window=` 束縛時に `attachStatics` 直後で呼ぶ)、seed 済み
  interface コンストラクタ + `DOMException` を `Object.defineProperty` で window プロキシ
  の *ターゲット* に own プロパティとして定義 (get トラップの own-property 高速パスで
  Ruby 往復なし、識別子も一致: `window.DOMException === DOMException`)。host が既に
  解決する名前 (Event 等の host 製コンストラクタ) は上書きしない。→
  Document-createElementNS **1→72/596**、Document-createElement **0→20/147**
  (dom 1022→1113)。再発パターン (他テストの `window.X` も恩恵)。
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
- **Element `*AttributeNS` + Attr ノード一式** (Dommy)。attributes.html を
  **7→47/67** に。内訳:
  - `getAttributeNS` / `setAttributeNS` / `hasAttributeNS` / `removeAttributeNS` /
    `getAttributeNodeNS` / `setAttributeNodeNS` を実装し `__js_call__` に配線。新しい
    `Internal::Namespaces.validate_and_extract` が WHATWG DOM の "validate and
    extract" を実装 (NCName/QName 検証 → InvalidCharacterError、prefix と namespace
    の整合性 → NamespaceError、`xml`/`xmlns` の特例)。両バックエンドが NS ストレージを
    実装 (Nokogiri はフル NS、Nokolexbor は null 名前空間に縮退)。(7→22)
  - **set-an-attribute-value の prefix 保持**: 既存の (namespace, localName) 属性を
    別 prefix で再 set したとき、値のみ変更し prefix は保持 (以前は prefix が変わって
    いた)。
  - **`Attr.textContent` / `Attr.specified`**: `Attr#__js_get__`/`__js_set__` に追加
    (textContent は value を返す/書く、specified は常に true)。テストヘルパー
    `attr_is` がこれらを参照するため大量の "(object) null" 失敗を解消。(22→34)
  - **非 NS の `setAttribute`/`toggleAttribute` の空名チェック**: 空 qualifiedName で
    InvalidCharacterError (corpus は空文字のみ無効を要求; `"0"`/`":"` 等は valid)。(34→36)
  - **Attr ノードの同一性キャッシュ**: `NamedNodeMap` が `[namespace, localName]` を
    キーに Attr インスタンスをキャッシュし、`el.attributes[i]` /
    `getAttributeNode(NS)` がすべて同一オブジェクトを返す。`setAttributeNode(NS)` は
    WHATWG "set an attribute" 準拠 (渡されたオブジェクトをそのまま採用、旧 Attr を
    detach して返す、別要素にバインド済みなら InUseAttributeError)。`Element#
    removeAttribute(NS)` は backend 削除の*前*に cached Attr を detach するので、保持
    された参照は `ownerElement === null` になり値を保つ。(36→47)
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

### `url-constructor` / `url-origin` — **完了** (888/888 + 401/401、Landed 参照)
かつて 0/1 だった原因 (testharness DOM 出力の NUL クラッシュ、`Response#json` の
lone-surrogate、URL の TypeError マーシャリング) はすべて解消。当時メモしていた
"Node object of unknown type" は、testharness が NUL 入りテスト名で createTextNode に
失敗 → 完了処理が落ち、`promise_test` が壊れた object を reject していたもの (proxy の
`has` トラップが全 true なので testharness が node と誤判定して整形) で、根本は上記 3 点。

## 残りのギャップバックログ (ROI 順)

大半は Dommy 側; ブリッジ側は明記する。

### dom/events — 伝播 + Event 定数 + 構築/辞書/once は完了 (Landed)
`Event-propagation` 7/7、`Event-constructors` 14/14、`Event-initEvent` 12/12、
`CustomEvent` 3/3、`AddEventListenerOptions-once` 4/4 は完了。残り:
- **`EventListenerOptions-capture` (2/4)**: addEventListener の options 辞書を遅延読みして
  `dummy` getter を呼ばないようにする (Event-constructors と同根だが host_call 経路なので
  `coerceConstructorArgs` が未適用)、および GC 圧力下のコールバック ID 再利用で残る stale
  capture リスナー (深いブリッジのライフサイクル問題)。
- **`Event-dispatch-bubbles-true/false` (各 3/5)**: `document.cloneNode(true)` (文書の
  ディープクローン) と `new Document()` へのクロスドキュメント append + クエリ。
- `Event-isTrusted` (0/1): プロパティ記述子の検査 (合成プロトタイプの構造的ギャップ)。

### URL コア — WHATWG basic URL パーサー — **完了** (Landed 参照)
- Ruby-`URI` を `Internal::UrlParser` に置換; `urltestdata.json` で 887/887。
- これ単体では解消しなかったもの: `url-constructor`/`url-origin` は依然 0/1。今は
  ハーネスのデータ供給の問題 (`Response#json` の lone-surrogate + "Node object of
  unknown type" マーシャリング — 上記) がボトルネックで、パーサではない。これらの修正が
  次に大きい `url` レバー (1 つの `promise_test` の裏に ~887 ケースが隠れている)。

### Attributes (attributes.html 47/67 — 残り 20 件)
Element `*AttributeNS`、Attr ノードの同一性、textContent/specified、空名検証は
**完了** (Landed 参照)。残りは難度・リスクの高いものが中心:
- **NamedNodeMap の own-property 列挙** (6 件)。`Object.getOwnPropertyNames(
  el.attributes)` がインデックス (`"0".."n-1"`、enumerable) + qualified name
  (non-enumerable) を返すべき。ブリッジの `makeHandler` には C バッチで array-like 用の
  `ownKeys` + `getOwnPropertyDescriptor` トラップが入った (インデックスは own 化済み) が、
  NamedNodeMap の **named property (qualified name) を non-enumerable own として公開** する
  部分と、HTML 文書中の HTML 要素は「全小文字の qualified name のみ」を named property に
  するカーブアウトが未対応。
- **同名属性が複数あるケース** (`First set attribute is returned` / `setAttribute should
  set the first attribute …`、~6 件)。Nokogiri/HTML は要素ごとに同名属性を 1 つしか
  持てないため、重複属性 (パース由来等) を表現できない。
- **libxml2 の `xmlns` 特殊扱い** (1 件)。`setAttributeNS(XMLNS, "xmlns", …)` の
  namespaceURI が取れない (libxml2 が名前空間宣言として扱う)。
- **`removeAttribute` の qualifiedName 横断マッチング** (1-2 件)。`setAttributeNS("x",
  "foo", …)` した属性を `removeAttribute("foo")` (qualifiedName 一致) で消す挙動 +
  cached Attr の detach キー整合。
- `document.implementation.createDocument` 未実装 (1 件)、inline style の toggle、
  非 HTML 要素の大文字属性 (createElementNS の case 保持に依存) 等。

### `Element-classlist` — **完了** (1420/1420、Landed 参照)
順序付き集合化で完全グリーン。

### createElement / createElementNS (createElement 123/147, createElementNS 534/596)
文書型対応 + window コンストラクタ + 検証 + iframe + 名前空間メタデータ + Node 定数で
大きく前進 (Landed 参照)。残り (両ファイル計 ~86) はほぼ **緩い古いケース** で、追わない:
`f}oo` / `;foo` / 先頭結合文字 / `￿` (XML Name production 的に無効) や `f:o:o` (コロン 2 個)
/ `0:a` (prefix が数字始まり) を valid 扱いする古い WPT 期待値。canonical 実装 (および実
ブラウザ/jsdom) でも落ちる。

### ノードの命名 / ノードタイプ — 完了 (Landed 参照)
- `Text`/`Comment`/`DocumentFragment`/`DocumentType` の `nodeName` は修正済み。残る
  Node-nodeName の失敗 1 件は外来名前空間の *要素* の大文字小文字で、上記の
  createElementNS 項目に属する。

### URLSearchParams (残り = urlsearchparams-constructor 21/27)
- `sort` (17/17) と ライブ `for…of` (`urlsearchparams-foreach` 6/6) は **完了** (Landed 参照)。
- 残るは `urlsearchparams-constructor` の 6 件: sequence-of-sequences のバリデーション
  (`new URLSearchParams([[1]])` は throw すべき)、unpaired-surrogate の置換 (`U+d835` →
  `�`)、レコード引数が全プロパティを読む件 (DOMException 引数)、NUL バイト入りキーの
  切り詰め、カスタム `[Symbol.iterator]`。

### `undefined` vs `null` (ブリッジ) — **完了** (Landed 参照)
- `dehydrateArgs` + `Dommy::Bridge::UNDEFINED` センチネルでトップレベル引数の `undefined`
  を `null` と区別。URL の base、`has`/`delete` の値、`createElement(NS)` の DOMString
  強制変換に適用。url-statics + searchparams-delete/has が完全グリーンに。

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
- `implementation.createDocumentType` / `createDocument` / `createHTMLDocument`、
  `Node.isEqualNode`、`createProcessingInstruction` は **完了** (Landed; Node-isEqualNode
  9/9)。`createDocument`/`createHTMLDocument` は window 非依存の独立 Document を生成する
  ので、まだ vendor していない `dom/common.js` ベースのテスト群のセットアップ要件も
  満たせるようになった (それらの追加 vendor は今後の作業)。
- **ノード wrapper の identity** (childNodes の残り 2 件): Nokogiri の `add_child` がテキスト
  ノードを再生成するため、`createTextNode` で得た wrapper の backend 参照が append 後に古く
  なり `childNodes[i] === kid` が崩れる。`append_child` が add_child の戻り値で wrapper を
  re-key する必要がある。`new Document()` へのクロスドキュメント append も同様。
- **Proxy `has` トラップがすべてに `true` を返す** (`host_runtime.js`)。array-like
  コレクションのインデックスは C バッチで範囲チェックするようにした (`2 in nodeList` は
  false) が、それ以外の name は依然 `true`。`"nodeType" in anyProxy` 等のダックタイピングを
  欺く潜在バグ。実メンバーシップ (symbols/HKEY/メソッド/expando/プロトタイプ) への厳格化は
  正当に null な DOM プロパティ (`firstChild`) に注意が要る。
- **Proxy `set` トラップが読み取り専用のホストゲッターを expando でシャドウする。** Dommy
  が write を処理しないとき、ブリッジはターゲットに JS 側 expando を退避する; そのプロパティ
  が実際にはホストの *ゲッター* (例 `classList`、`tagName`) だと、expando が以後それを恒久的
  にシャドウする。`classList` は Dommy の PutForwards で回避したが、一般則として誤り —
  ホスト公開の読み取り専用 name への未処理 write はドロップ (または strict モードで throw)
  すべきで、シャドウすべきでない。ホストが「この name は自分が所有する (読み取り専用)」 vs
  「自由な expando スロット」を通知する必要がある。
