# ブラウザ互換性ロードマップ TODO

happy-dom / jsdom に対抗して Dommy + Dommy::Js::Quickjs の規格互換性を高めるための作業リスト。

**第1トランシェ (整合性の即効 + D1a) 完了 (2026-07-05)** — `total 40173/40443 (99.3%)` に到達:

```
                  before (基準)          after (第1トランシェ)
total     37037/37800 (98.0%, 1 errored)  40173/40443 (99.3%, 0 errored)
```

**B3 第1弾 (webstorage + FileAPI/blob vendor) 完了 (2026-07-05)** —
`total 41628/41908 (99.3%)`、fully-green 211 ファイル (+16)。webstorage (1172/1200) と
FileAPI/blob (256/260) を新規 vendor し分母を +1465。Storage の WebIDL legacy-platform-object
準拠化と Blob の `sequence<BlobPart>` / `[Clamp]` slice / bytes() / endings 対応。詳細は 戦線B B3。

第1トランシェの中身と効果:
- **A0/A1a (同一原因): `WptRunner` の `<iframe src>` ナビゲーション未実装**を修正。
  window `load` 発火前に静的 iframe を wire する必要があるため、boot を
  `execute_scripts: false` + 手動 `ScriptBoot` に組み替え。効果:
  `ParentNode-querySelector-All` 0(errored)→1961/1975、`Element-matches` 0/1→668/669、
  `Document-createElementNS` 121→562/596、`Document-createElement` 49→115/147。
  (分母が ~2600 増えたのは、従来ハングして脱落していた iframe テストが実行されたため)
- **A1 検証系は net-new 不要だった** — WHATWG qualified-name 検証
  (`Internal::Namespaces.validate_and_extract`) は既に正しく失敗ゼロ。ロードマップの
  「検証実装が足りない」という前提は誤りだった。
- **1c: `Element#nodeValue` → `null`** (element.rb) — createElementNS の残り 221 を回収。
- **1b: ハーネス堅牢化** — `JSON.parse("null")` が全ファイルを道連れにするのを防ぐガード。
- **D1a: セレクタ AST グローバルキャッシュ** (下記 戦線D 参照) — `matches?` 8.5x、
  mutate+querySelector 3.3x 高速化、conformance 回帰ゼロ。

**ナビゲーションモデル N0–N3a 完了 (2026-07-08)** — 設計 `docs/navigation-design.md`。
Dommy を「単一文書」から「ページ遷移を含むセッション」へ。戦線C の Turbo unit 52.6% 頭打ちの
直接原因(default action 不在 + JS 起点ナビ未接続)への布石:
- **N0/N1**: `NavigationDelegate` ポート + `<a>`/`<area>` の follow-the-hyperlink activation
  behavior(`el.click()`/synthetic 両経路)+ fragment 同一文書ナビ + `HashChangeEvent`(real
  event, full URL)+ `location.assign/replace/reload/href=` の cross-doc 配線。
- **N2**: `SubmitEvent`(submitter 公開)+ `form.requestSubmit()/submit()` を delegate へ配線
  (form data set は `FormSubmission#submit!` 再利用)。
- **N3a**: **core `Browser` が自身の NavigationDelegate** になり cross-document 文書置換を実装
  (`navigable:`/`Browser.visit`)。`Navigation::Fetcher`(Resources 上の redirect 追従)+
  `Navigation::JointHistory`(タブ履歴)+ 置換パイプライン(fetch→旧 pagehide/unload→旧
  Runtime dispose→新 Window+realm+ScriptBoot)。ナビはタスク(JS 起点は drain 境界で遅延
  フラッシュ)。既定 `Browser.new(html)` は NullDelegate で挙動変更ゼロ。
- 4スイート green 維持(dommy 3368 / quickjs 598 / dommy-rack 232 / capybara 1259)。
- **N4-1 (2026-07-08)**: form submission ロジックを `HTMLFormElement#__run_form_submission__`
  に集約(bare `Event("submit")` の 4 箇所を real SubmitEvent + delegate へ格上げ)。navigable
  Browser は submit ボタン click で実ナビ。
- **N4-2 (2026-07-08)**: **確認済みの実 gap を解消** — dommy-rack は JS 起点ナビ
  (`location.href=` / `window.location=` / `form.submit()`)を辿れていなかった(window は
  NullDelegate)。submit ボタンに `SubmitButtonActivation`、`window.location=` setter 追加、
  dommy-rack が `PageNavigationDelegate` を各 window に配線(deferral + stale window ガード +
  `perform_page_navigation`)、capybara の `js_click` link/submit 分岐と `js_submit` を削除。
  **実 quickjs 統合 6 tests 追加**(既存は NullRuntime で gap 未カバーだった)。4スイート green
  (dommy 3370 / quickjs 604 / dommy-rack 232 / capybara 1259)。
- **N4-2 仕上げ (2026-07-08)**: delegate 経路で `location.replace()`/`reload()` が履歴エントリを
  置換(push でなく)+ フォームの `_method` override(POST→PATCH/PUT/DELETE)を適用(Rack::
  MethodOverride 無しのアプリでも動作)。
- **インライン `on*=` ハンドラ (2026-07-08)**: `onclick="..."` 等の content 属性を boot 時に
  IDL onclick= 経路でコンパイル(`this`=element / `event` in scope)。ScriptBoot に集約したため
  Browser/rack/capybara/WPT 全消費者で有効。boot 後に挿入された要素(innerHTML/setAttribute)は
  スコープ外(framework は addEventListener を使う)。`<body onload>` 等 window-reflected handler は
  window へ配線。inline onclick で window.location= → 実ナビも確認。JS は modern ES に書き直し。
- **window event handler IDL (2026-07-08)**: `window.onload = fn`(/ onresize / onpopstate / …)が
  従来 JS global に stash されるだけで**発火しなかった** pre-existing gap を解消。bridge set trap で
  window の `on*` 書き込みを host へ通し、Window が既知ハンドラ名を intercept(それ以外の on 接頭辞
  global は素の expando 維持)。`EventTarget#set_on_handler` を Element から hoist して共有。
- **N3b (2026-07-08)**: core Browser の **meta refresh 追従**(replace 扱い、自己 refresh ループ cap)
  + **opt-in same-origin スコープ**(`Browser.visit(same_origin: true)` で cross-origin target/redirect を
  block。permissive adapter 経由で core Fetcher が cross-origin redirect 追従する穴を解消)。
- **WPT `the-location-interface` vendor (2026-07-08)**: web-platform-tests を shallow+sparse
  checkout(`html/browsers/history` のみ)して自己完結分 8 files を vendor = **11/11 subtests green**
  (location property getters href/host/hostname/origin/pathname/protocol + toJSON + prototype shape)。
  `history-traversal` は upstream に該当 dir 無し、他 history dir は iframe/nav 依存で vendor 不可。
  object-shape 系(preventExtensions / Symbol.toPrimitive / valueOf の WebIDL descriptor)は Dommy の
  bridge Location が real Location.prototype を持たないため fail → drop。
- **WPT `html/webappapis/scripting/events` vendor (2026-07-08)**: 同 checkout から自己完結分 2 files
  = **7/7 green**(`event-handler-javascript` = javascript: URL handler / `event-handler-non-content-
  document-idl-attributes` = browsing context 無し文書の on* IDL)。dir 全体は 24 files 中 low-yield
  (下記 gap 依存 + 0/0 no-result 多数)のため 2 files のみ keep。
- **発見した follow-up gap 群 → 全て修正 (2026-07-08)**:
  - ✅ `location.port` = default port で `""`、`location.host` = 非 default port を含む(WHATWG 準拠)。
  - ✅ **HTMLBodyElement/FrameSet の window-reflecting onX IDL**: `body.onload = fn` が window.onload
    へ reflect(`WindowReflectingHandlers` module)。`body-onload.html` green。
  - ✅ **event handler の返り値処理**: `onclick="return false"` / **`onsubmit="return false"`**(頻出)が
    cancel、onerror on Window は `true` で cancel(WHATWG event handler processing algorithm、
    `Listener#event_handler?` フラグ + dispatch で返り値処理)。addEventListener は不変。
    `eventhandler-cancellation.html` 15/15 green。
  - ✅ **inline handler の lexical scope**: `[element, form owner, document]` scope chain を with-wrap で
    実装(`onclick="getElementById(...)"` 等が解決)。core cases green(window.print/domain stub 依存の
    WPT 一部は未 vendor)。
  - **副産物**: `html/webappapis/scripting/events` の vendor が 2→4 files(body-onload +
    eventhandler-cancellation 追加、23/23 green)。
- **残**: **iframe パイプライン共通化はスコープアウト**(iframe は realm 内サブフレームロードで N3a の
  top-level と別物、WPT 固有処理を含み core 未対応 = リスク>価値)。dommynx フォールバック削除(別リポ)。

**残った新カテゴリ (次トランシェ候補)**: createElement(NS) の XML/XHTML document で
`":"` / `":foo"` / `"foo:"` 等が Makiri XML の「not a well-formed XML name」で弾かれる
(34+32=66件)。Dommy の検証は spec 通り通すが Makiri XML backend がより厳格 = backend 限界。

前提: バックエンドは Makiri (Lexbor) 一本。セレクタ AST matcher・CSS cascade /
getComputedStyle・Shadow DOM・Custom Elements は実装済み。大規模な基盤置き換えは不要で、
残る構造的投資はブリッジのバッチ化 (B4) のみ。

---

## 戦線A: 現行コーパスの回収 (即効、残り 763 サブテスト)

- [x] **A0. 回帰修正: `dom/nodes/ParentNode-querySelector-All.html` のハーネスエラー** — 完了
  - 原因は「AST matcher の集計ズレ」ではなく `WptRunner` の `<iframe src>` 未ナビゲーション。
    A1 と同一原因だった。`wpt_runner.rb` の boot 組み替え + iframe wiring で解決 (0→1961/1975)。
- [x] **A1. createElement / createElementNS クラスタ** — 完了 (562/596, 115/147)
  - 573 の内訳は「検証不足」ではなかった: 488 = iframe src 未ナビ (A0 と同一)、85 =
    `Element#nodeValue` undefined バグ。検証 (`Namespaces.validate_and_extract`) は既に正しかった。
  - 残り 66 = Makiri XML backend の name 厳格性 (別カテゴリ、上記参照)。
- [x] **A1b. DocumentType の full tree integration** — 完了 (2026-07-09)
  - 従来 `document.doctype` は synthetic な Ruby スタブ (常に `DocumentType.new("html")`) で
    Makiri の doctype node と非連結。このため `childNodes` に doctype が無く、
    `documentElement.parentNode` が null、doctype の tree ops が全て DISCONNECTED だった。
  - **Tier 1 (Dommy のみ)**: parse 済み文書の doctype を Makiri node backed 化。
    `DocumentType` を dual-mode (node-backed / synthetic) に。`doc.doctype` は
    `Backend.internal_subset` から wrap、`build_wrapper_for` に document/doctype ケース追加。
    **鍵**: `wrap_node(backend_doc) → Dommy::Document` マッピングで
    `documentElement.parentNode === document` を実現 (spec 準拠の親子一貫性)。
  - 波及して顕在化した既存バグも是正:
    - `compareDocumentPosition`: `node_ancestor_chain` を document まで含めるよう変更 +
      Document を `compare_backend_node` で backend node に解決 (1444/1444)。
    - `Document#contains?`: `.ancestors` (document を除外) 依存をやめ parent walk に (1482/1482)。
    - `NodeIterator`: document root への descend を `backend_node_of` で対応、
      document-child 削除経路 (`document_remove_child` / `__internal_remove_doctype__`) に
      pre-removing steps を配線 (NodeIterator 766/766、-removal 22/22)。
    - `Range.intersectsNode`: root 不一致→false / parent nil→true の spec ステップを追加 (2356/2356)。
    - `Element#parentElement`: 非 element 親 (document) を返さないよう `.element?` ガード
      (Alpine の `findClosest` が `document.matches` を呼んで死ぬ回帰を修正)。
  - **`createDocumentType`**: Makiri 0.7.0 の `HTML::Document#create_document_type` factory を
    使って node-backed 化 (tree に入れられる)。factory は name を case 保存する (Makiri 側で
    ASCII-lowercase を除去済み — createDocumentType は case-preserving) ので、node-backed doctype は
    name/publicId/systemId を node から直接返す。`DocumentType#cloneNode` も追加。
    makiri 0.6.0 (dommy standalone bundle) では factory 不在 → synthetic fallback。
  - **`createDocument(ns, qname, doctype)`**: Makiri 0.7.0 が `XML::Document#create_document_type`
    (case 保存) も追加したので doctype を配置できるように。Makiri は arena 間で node を move
    できないため、渡された doctype を新 doc の backend に **name/publicId/systemId から再生成**
    (adopt 相当) して root の前に挿入。backend が id を拒否した場合 (例: system id に `"` と `'`
    が混在 → XML serialize 不可) は throw せず未配置に degrade (createDocument は id を検証しない)
    → `Node-isEqualNode` **9/9** (旧 expected-fail 解消)。
  - 結果: dommy 3400/0、quickjs (WPT_HEAVY) 613/0、回帰ゼロ。ベンチ回帰なし。
- [ ] **A2. 長い尻尾の回収** (優先度順)
  - [ ] `css/cssom/getComputedStyle-pseudo.html` 4/28 — ::before/::after の computed style (cascade は pseudo-element rule 対応済みのはずなので配線を確認)
  - [ ] `dom/observable/tentative/observable-from.any.js` 25/48 ほか observable 系 ~30 — 非同期 iterable 変換など (observable_runtime.js ポリフィル)
  - [x] `html/dom/aria-element-reflection.html` **8→27/27 全 green** (2026-07-11) — WHATWG「reflecting
    element references」の valid-scope 検証(explicit attr-element は要素の shadow-including ancestor の
    shadow-including descendant のときのみ observable → shadow tree への cross は null、ancestor scope は許可)
    + 複数系 getter は content 属性欠如で null(≠[])+ singular は aria-activedescendant のみ + 型不一致は
    TypeError + 複数系を per-property memoized live list 化([SameObject])+ **cross-document adoptNode の
    descendant wrapper reseat**(import 済み copy へ全 live 子孫 wrapper を並行 walk で移設 = adoption 全般の改善)。
  - [ ] `css/css-color/parsing/color-computed-hsl.html` 3735/3753 (残18)
  - [x] **`dom/nodes/Node-cloneNode.html` 132→135/135 全 green** (2026-07-11) — cloneNode が
    createElementNS メタデータ(namespaceURI/prefix/localName/qualified name)を clone に引き継ぎ、
    interface class を local name で解決(HTMLUnknownElement 化を防止); Document#URL は browsing
    context 無し文書で "about:blank"; compatMode は XML 文書で "CSS1Compat"(常に no-quirks)。
  - [x] **`dom/nodes/attributes.html` 62→67/67 全 green** (2026-07-11) — 属性 qualified-name の
    case-sensitivity を WHATWG 準拠に: lowercase は「HTML 名前空間の要素 かつ HTML 文書」の時のみ
    (`case_sensitive_attribute_names?` の predicate 修正 + HTMLElement override が文書種別を見るように)。
    非HTML/null-ns 要素の `setAttribute` を case 保存 NS 経路に(HTML backend の lowercase 回避)、
    getNamedItem/removeNamedItem を case-aware に(`el.attributes["A:B"]` 解決)、NamedNodeMap の
    supported property names は HTML-in-HTML でのみ大文字含む名を除外、removeAttribute が namespaced
    Attr を正しく evict(ownerElement=null → setAttributeNode の in-use 誤検知解消)、`*AttributeNS`
    が undefined namespace を null に coerce(WebIDL nullable DOMString)。dommy 3400/0・quickjs 614/0。
  - [x] **Range foreign/xml サブテスト全 green** (2026-07-11) — DocumentType tree integration +
    createDocument doctype 配置の副産物で foreignDoc/xmlDoc/processingInstruction のレンジ比較が緑化。
    `Range-compareBoundaryPoints` 9313/9313・`Range-isPointInRange` 5733/5733・`Range-comparePoint`
    5580/5580・`Range-intersectsNode` 2356/2356 全緑。`FOREIGN_RANGE`/`XML_PI_POINT` expected 撤去。
  - [x] **ChildNode `before`/`after`/`replaceWith` + document 階層検証** (2026-07-12) —
    `Internal::ChildNode` mixin に WHATWG アルゴリズムを一本化(viable previous/next sibling を
    引数ノード除外で解決 → 引数 detach 後に reference child 確定 → fixed anchor で forward 挿入)し
    Element と leaf CharacterData(Text/Comment/PI)で共有。従来は各クラス別実装で multi-node 引数を
    逆順挿入 + viable-sibling 未対応だった。JS ブリッジで `(Node or DOMString)...` union coercion
    (null→"null"/undefined→"undefined")を Ruby 越境前に実施。加えて Document 親の pre-insertion
    hierarchy(step 6: 単一 element / text 不可 / doctype 配置規則)を `ensure_document_insertion_validity!`
    で enforce(append/prepend/appendChild/insertBefore/replaceChild/replaceChildren、node_type は
    backend 非依存で XML 文書も対応)、Fragment の insertBefore/replaceChild も検証経路に。
    `ChildNode-before/after/replaceWith` 45/45/33、`ParentNode-append/prepend` 25/22 全緑、
    `ParentNode-replaceChildren` 30/31 を vendor。続けて **replaceChild/insertBefore クラスタ**も回収:
    leaf 親(CharacterData/DocumentType)の replaceChild は step 1 で HierarchyRequestError(NotFoundError
    でなく)、Element#replace_child の「次の兄弟で置換」時の anchor 前進、document replace validity の
    「既に element/doctype がある」判定(置換対象を除外)と位置判定(doctype following / element preceding)の
    分離、insertBefore の NotFoundError→step6 順序、**cross-document doctype adoption**(adopt_node が宛先
    backend に doctype を再生成 + wrapper/owner 付け替え、document_replace_child は旧 doctype を先に外して
    Makiri の単一 doctype ガード回避、DocumentType#document 追加)。`Node-replaceChild` **29/29**・
    `Node-insertBefore` **39/40** を vendor(pre-insertion-validation-notfound.js の順序テストも緑)。
    さらに周辺も回収: adoptNode(Document)→ NotSupportedError、`normalize()` を ParentNode に一本化して
    DocumentFragment/ShadowRoot でも隣接 Text を先頭ノードへマージ(従来 Fragment は空 Text 削除のみの stub)。
    `Node-removeChild` **28/28**・`Node-normalize` **4/4**・`DocumentType-literal` **1/1**・
    `Document-adoptNode` **2/4** を vendor(重複 map key も掃除)。dommy 3400/0・quickjs 641/0。
    残: DocumentType wrapper-identity(cloned doctype re-insert、ParentNode-replaceChildren の 1 fail)、
    insertBefore/replaceChild 第2引数の WebIDL 型検査(stub 関数の arity=0 のため WPT helper が引数を
    落とし副作用が出る → 要 per-method arity)、adoptNode の XML-invalid 名(`x<`/`:good:times:`、Makiri
    XML backend の name strictness)。`remove-unscopable` は `with` スコープ + Symbol.unscopables が必要で保留。
  - [x] **CharacterData 一式 + remove/createComment/createTextNode** (2026-07-12) —
    CharacterData の offset/count を WebIDL unsigned long(ToUint32 で負値/2^32 超を wrap)+ UTF-16
    code unit 単位に(astral 文字=2、UTF-16LE buffer slice)、null→"null" / undefined→"undefined" の
    DOMString coercion、substringData/appendData の必須引数 arity。`CharacterData-data/appendData/
    insertData/deleteData/replaceData/substringData` 全緑(16/14/18/18/34/28)+ `Text-splitText` 6/6。
    さらに ChildNode#remove を void→undefined(従来 null)化、createComment/createTextNode(null)→"null"。
    `CharacterData-remove` 12/12・`Element-remove` 4/4・`Document-createComment`/`createTextNode` 6/6 を vendor。
    dommy 3400/0・quickjs 652/0。残: 非対応は無し(このクラスタは完了)。`Element-getElementsByTagNameNS`
    は 10/16 で保留(namespace prefix マッチ = Makiri XML name/namespace 系)。
  - [x] **getElementsByTagName(NS) の spec 準拠マッチング** (2026-07-12) —
    従来 `root.css(name)`(HTML では case-insensitive・qualified name ベース)で誤マッチ。
    NS 版は local name を case-sensitive 完全一致 + namespace で判定(prefixed `test:body` や
    `BODY` の case を正しく扱う)。非NS版は WHATWG qualified-name アルゴリズム(HTML 文書の
    HTML-namespace 要素はクエリのみ ASCII-lowercase して比較 → 大文字 localName の HTML 要素は
    never match、非HTML namespace / 非HTML 文書は case-sensitive)。qualified name は case 保存の
    local_name + prefix から再構築(backend node.name は lowercase 済みで信頼不可)。
    `Element/Document-getElementsByTagNameNS` 16/16・14/14 全緑、`Element/Document-getElementsByTagName`
    17/19・16/18。HTMLCollection.namedItem を `name` は HTML-namespace 要素のみ一致に修正
    (own-property enumeration が緑化)+ Attr.baseURI を node document の base URL に(`Node-baseURI` 9/9 vendor)。
    残2は HTMLCollection の ABI メソッド(item/namedItem)を prototype 経由で解決する必要
    (expando shadowing、proxy method-resolution の core 変更で全 proxy に波及するため保留)。
    dommy 3400/0・quickjs 657/0。
  - [x] **lookupNamespaceURI / lookupPrefix / isDefaultNamespace の spec 準拠化** (2026-07-12) —
    WHATWG "locate a namespace/prefix" を再実装。従来 backend の `namespace_definitions` に依存し
    setAttributeNS で足した xmlns 宣言を見落とし + null namespace と HTML default を区別できなかった。
    node 種別ごとに起点要素を解決(element=自身 / child=祖先要素 / attr=owner / document=documentElement、
    fragment・doctype=なし)し、要素の namespace(prefix 一致)+ xmlns 属性(xmlns namespace の attribute)を
    walk。xml/xmlns は暗黙 binding。Document/DocumentType/Attr にも dispatch を追加(従来 nil に落ちて
    isDefaultNamespace が nil を返していた)。`Node-lookupNamespaceURI` **0→75/75 全緑**。加えて
    `Element-setAttribute`/`Element-removeAttribute`(2/2)を vendor。dommy 3400/0・quickjs 657/0。
  - [x] **null coercion + insertAdjacent 検証ほか** (2026-07-12) —
    `getElementById(null)` / `matches(null)` を "null" に coerce(id="null" 要素 / `<null>` タグに一致)。
    `insertAdjacentElement/Text` は不正 position で SyntaxError(ASCII case-insensitive)、documentElement の
    beforebegin/afterend で2番目の root を足すと HierarchyRequestError。`Element-matches` **669/669**・
    `Document-getElementById` **18/18**・`Element-insertAdjacentElement/Text` **6/6**・`rootNode` 5/5・
    `Node-isConnected-shadow-dom` 2/2 を vendor。dommy 3400/0・quickjs 666/0。
  - [x] **webkitMatchesSelector ルーティング + querySelector 群** (2026-07-12) —
    `webkitMatchesSelector` が Element dispatch で nil に落ちていた(js_methods 未宣言)→ `matches` へ配線し
    js_methods にも追加。`Element-webkitMatchesSelector` **7→669/669**(662 subtests を1行で解放)。
    `ParentNode-querySelector-All`(1961/1975、残は :link/:visited・detached root の :target・no-namespace
    `|div`/`|*`)+ `querySelectors-exclusive`/`-namespaces`(1/1)を vendor。quickjs 670/0。
  - [x] **parentElement の null 化** (2026-07-12) — Text/Comment は parentElement 未対応で undefined、
    DocumentFragment は parentNode/parentElement 未対応だった。親が element の時のみ返す(document/fragment 親は
    null)よう Element#parentElement に合わせた。`Node-parentElement` **12/12**・`DocumentType-remove` 4/4 を vendor。
    quickjs 672/0。(`Event-init-while-dispatching` の initUIEvent/initMouseEvent/initKeyboardEvent は UIEvent
    interface 新規追加が必要で保留)
  - [x] **Attr.ownerDocument (adoption 追従) + Range.comparePoint 引数検証** (2026-07-12) —
    Attr.ownerDocument/baseURI を owner element の現在の document 由来に(adoptNode で attribute の
    ownerDocument も更新)、ownerDocument getter も公開(従来 undefined)。Range.comparePoint は node 引数の
    Node 型チェックを最初に(null → TypeError)。`Node-mutation-adoptNode` 2/2・`Range-comparePoint-2` 3/3 vendor。
    quickjs 674/0。(`Element-closest` の残2は `:invalid` / `:has(> :scope)` セレクタ対応)
  - [x] **`CharacterData-surrogates` = 対応済み(fail-loud で確定)** (2026-07-12) — サロゲートペアを割ると
    lone surrogate が生じ Ruby の UTF-8 String では表現不可(基盤制約)。WTF-8 化の大改修は費用対効果が合わず、
    かつ「ペアを割る = 呼び出し側の UTF-16 offset バグ」なので U+FFFD で握り潰すより例外の方が妥当。事故的に漏れていた
    `Encoding::InvalidByteSequenceError`("\xDF on UTF-16LE")を、意図明確なメッセージへ投げ直すだけに留めた
    (`utf16_slice` の rescue 数行、挙動不変)。WPT 8 subtests は諦め(未 vendor)。
  - [x] **textContent setter の nullable / subtree 保存 / Fragment 対応** (2026-07-12) —
    textContent は nullable DOMString: null/undefined は共に子を消去(undefined が "undefined" にならない)。
    子の置換を backend の `content=`(subtree ごと解放)でなく unlink で行い、削除ノードが自身の子孫を保持。
    DocumentFragment の setter も実装(従来 no-op)。`nullable_dom_string` を Internal::ChildNode に共有。
    `Node-textContent` **48→81/81 全緑**。quickjs 676/0。
  - [x] **ブリッジ: WebIDL 関数 arity + read-only collection method の prototype 同一性** (2026-07-12) —
    ①② を安全な追加変更として実装。② メソッド stub は rest params で `.length`=0 だったのを `METHOD_ARITY` マップで
    仕様 arity をスタンプ(seed stub + get-trap methodCache 両方)。arity が正しくなったので `.length` 分岐する
    WPT helper が正しく引数を渡すようになり、insertBefore の reference-child 検査(欠落/非Node → TypeError)を
    安全に再導入 → `Node-insertBefore` **40/40**。① 読み取り専用の collection op(item/namedItem/getNamedItem(NS))を
    HTMLCollection/NodeList/NamedNodeMap の prototype に seed し、get trap で prototype 関数へ直接解決
    (`coll.item === HTMLCollection.prototype.item`、expando shadow 可)。mutating op は epoch-bump の
    get-trap 経路のまま。`Element/Document-getElementsByTagName` **19/18 全緑**・`attributes-namednodemap` **8/8**。
    dommy 3400/0・quickjs 676/0、回帰ゼロ。(全メソッドの prototype 統一は attr-cache/epoch の per-proxy 最適化を
    壊すため見送り、read-only collection に限定した narrow fix)
  - [x] **⑦ Makiri XML name 厳格性(cross-import loose 要素名)= 完了** (2026-07-12) —
    `import_node`(=adoptNode)が HTML 由来の DOM-lenient 要素名(`:good:times:`/`x<`/`0:a`/`f}oo`)を
    `not a well-formed XML name` で弾いていた。依頼 `todo-dommy-loose-element-import.md` 起票 → **Makiri v0.8.0**
    で対応(`h2x_make` が `MKR_XML_MUT_BAD_NAME` 時に `mkr_xml_new_loose_dom_element` へフォールバック、ns 直接渡しで
    namespaceURI 保存、非シリアライズ)。Dommy を makiri **`>= 0.8.0`** に bump(dommy gemspec/Gemfile)し
    `Document-adoptNode` を **4/4** に更新。Dommy 側のコード変更は不要(`adopt`→`import_node` が通るだけ)。
    dommy 3400/0・quickjs 676/0、回帰ゼロ。lenient **属性**名の cross-import は依然 fail-closed(必要なら別TODO)。
  - [x] **④ UIEvent interface + legacy init メソッド** (2026-07-12) — `UIEvent`(view/detail)を新設し
    Event と MouseEvent/KeyboardEvent/CompositionEvent の間に挿入(DOM 階層: MouseEvent→UIEvent→Event)。
    `initUIEvent`/`initMouseEvent`/`initKeyboardEvent`(initEvent 同様 dispatch 中は no-op)+ MouseEvent の
    screenX/screenY を追加、constructor 登録、interface prototype chain 更新。`Event-init-while-dispatching`
    **2→5/5**。dommy 3400/0・quickjs 677/0。
  - [x] **Event subclass constructors + 属性 prototype 化(④の延長)** (2026-07-12) —
    UIEvent/MouseEvent/KeyboardEvent/WheelEvent/FocusEvent/CompositionEvent の readonly 属性を
    interface prototype に seed(WebIDL 準拠 → `"view" in ev`/hasOwnProperty/getOwnPropertyDescriptor が解決。
    値は従来通り get trap が host から取得)。WheelEvent→MouseEvent→UIEvent→Event / FocusEvent→UIEvent の
    chain 追加(constructor は既存登録済み)、MouseEvent に buttons/relatedTarget、UIEvent の `view` を
    `Window?` 型検査、**JS の `class extends Event` が new.target.prototype をスタンプ**(non-Node interface の
    subclass も `instanceof` 成立、custom-element 経路の一般化)。`Event-subclasses-constructors` **9→49/49**。
    dommy 3400/0・quickjs 677/0、回帰ゼロ。
  - [x] **EventTarget 構築/subclass + セレクタ小物** (2026-07-12) — `composedPath()` を dispatch 終了後は空に、
    `class extends EventTarget` の再スタンプ(EventTarget の ctor が chain 配列に "Node" を含むため誤ブロック
    していた `!consultsStack` ガードを撤去; Node/CE 経路は既に early-return 済み)で instanceof + 追加メソッドが
    動作。`:is()`/`:where()`/`:matches()` の空 forgiving list を許可(matches nothing)。
    `EventTarget-constructible` 3/3・`has-basic` 18/18・`pseudo-enabled-disabled` 4/4・`is-where-basic` 15/15 を
    vendor(`:has()` basic / enabled-disabled は既に動作していた)。quickjs 682/0。
    残: `:has(:scope)`/`:has(> :scope)`(:has 内の scope binding)、`:invalid`/`:valid`(form validity)。
  - [x] **セレクタ群 + MutationObserver の未 vendor 回収** (2026-07-12) — 既に動作していた大量のテストを vendor:
    `:is/:where/:not`(is-where-not 18・not-complex 20・is-nested・is-where-error-recovery)、
    child-position(first/last/only-child 各5)、`scope-selector` 2/3(`:scope` on document は保留)、
    **MutationObserver** childList 38・attributes 42・characterData 23・disconnect 2・takeRecords 3・
    inner-outer 3(~112 subtests)。quickjs 697/0。残: `:scope` on document element、`MutationObserver-document`
    3 fail(document-level 監視 edge)。
  - [x] **document accessors + 追加 vendor** (2026-07-12) — `document.title-01` 4/4・`nameditem-01` 6/7 を vendor。
    残: nameditem の live named-access(name 属性動的変更)1 fail。quickjs 699/0。
    (Range-insertNode/surroundContents/cloneContents 等は iframe/cross-realm 依存で ⑥ に集約、未 vendor)
  - [x] **⑤ form validity: `:valid`/`:invalid` セレクタ + constraint-validation suite** (2026-07-12) —
    ValidityState / checkValidity / reportValidity は既に実装済みだったが `:invalid`/`:valid` は "degrade to
    no match" のままだった。matcher に `:valid`/`:invalid`(control の willValidate + validity.valid、form/
    fieldset は子孫 control 由来)、`:required`/`:optional`、`:read-only`/`:read-write` を配線。加えて未 vendor
    だった **constraint-validation suite ~800 subtests** を vendor(checkValidity/reportValidity 各130、
    validity-{valueMissing 78/typeMismatch/tooLong 63/tooShort 63/rangeUnderflow 47/rangeOverflow 49/valid 35}
    全緑 + patternMismatch/stepMismatch/badInput/customError/willValidate は既知 edge を expected 化)。
    dommy 3400/0・quickjs 713/0。残 edge: v-mode 正規表現、object/submit の willValidate、色 badInput。
  - [x] **⑥ iframe nested browsing context + per-frame realm (Phase A/B/C)** (2026-07-12) —
    設計は `docs/iframe-realm-design.md`(未コミット)。実装済み:
    - **Phase A**: bare/src-less で connect された `<iframe>` が lazy に blank `about:blank`
      Document + Window を生成(`content_document`/`content_window`、`html_elements.rb`)。
      src/srcdoc 付きは従来の host/test ナビ層に委譲(gate 済み、回帰なし)。
    - **Phase B**: 非グローバル Window proxy(= iframe の contentWindow)が初回 materialize 時に
      自前の constructor 群(Event/DOMException/Range/Node/… + JS builtins)を seed
      (`host_runtime.js` makeProxy フック → `exposeConstructorsOnWindow(p)`)。
      加えて interface 名は「callable だが非 constructable な host Constructor proxy」でも
      無条件に seeded ctor へ差し替え(`new cw.Event(...)` の "not a constructor" を解消)。
    - **Phase C(同一 VM)**: nested document 内での Range.insertNode 等が end-to-end 動作
      (cross-realm marshaling は同一 VM なので handle proxy がそのまま機能)。
    - 回帰テスト: `test_browser.rb#test_blank_iframe_content_window_has_its_own_constructors`
      (contentWindow constructors + `new cw.Event`/`new cw.DOMException` + iframe 内 Range)。
    - dommy 3400/0・quickjs 725/0。
    - **残(Phase D / B2 = マルチ realm 待ち)**: `dom/ranges/Range-insertNode.html`・
      `Range-surroundContents.html`(cloneContents/deleteContents/extractContents も同型、各 ~1840
      subtests)は調査の結果 **真の per-realm JS グローバルが必須**と判明。`common.js` は
      `var testDiv, paras, …`(bare グローバル)を宣言し、テストは actual/expected の2 iframe に対し
      `iframe.contentWindow.setupRangeTests()` / `.testRangeInput=` / `.run()` / `.testRange` を
      **独立した realm ごと**に行う。単一 QuickJS context(現行 gem)では親 + 2 iframe の
      `paras`/`run`/`testRangeInput` が衝突するため **B1 では原理的に不可**。
      - **決定(2026-07-12): B2(gem に追加 JSContext/realm を入れる)を本線に採択。**
        QuickJS は 1 runtime : N context で値の realm 跨ぎ受け渡しが可能。gem の汎用機能
        (サンドボックス/realm 隔離)としても筋が良い。
      - gem 宛の依頼を `/Users/maki/git/quickjs.rb/todo-dommy-realm-support.md` に作成
        (`vm.create_realm` → `Quickjs::Realm#{eval_code,define_function,call,global,dispose!}`、
        ランタイム共有 + cross-realm 値受け渡し + 独立 global の受け入れ条件つき)。
      - Dommy 側は本 API 前提で先行実装予定: `wire_iframes` で framed document の script を
        realm 上実行、`__rbHost` を realm へ敷く、`contentWindow` proxy の未知プロパティを
        `realm.global` へフォールバック。gem release 後に Range 系を vendor して回収。
      - across-globals の厳密 realm identity(`a.Node !== b.Node`)も B2 なら満たせる見込み。
  - [x] **realm 非依存の回収バッチ(gem realm 待ちの間)** (2026-07-13) — quickjs 726→734 test methods、~90 subtests:
    - `domparsing/createContextualFragment` **34/35**: `Range.createContextualFragment` の WebIDL 強制
      (0引数→TypeError、null→"null")。残1 = 動的挿入 script 実行(browser-level、expected)。
    - `dom/nodes` 8本 vendor: Element-children 2、DocumentFragment-getElementById 5、
      Element-matches-namespaced-elements 6、**getElementsByClassName-whitespace-class-names 5→26**
      (class トークン分割を DOM「ASCII whitespace」限定 + `.tok` セレクタ文字列を経由せず直接照合)、
      Text-wholeText 0→1(`Text.wholeText` 実装)、**append/prepend-on-Document 4→5**
      (Document の append/prepend/replaceChildren/insertBefore が cross-document node を adopt するよう修正、
      appendChild と同経路化)、Document-importNode 3→4(importNode の `deep` を WebIDL 既定 false に強制)。
    - 追加バッチ(同日): `dom/nodes` +2 vendor — DocumentType-remove 4/4、remove-unscopable 3/6。
      **`Element.prototype[Symbol.unscopables]` を実装**(ChildNode/ParentNode mixin の [Unscopable]
      メンバを null-proto の @@unscopables に。Element/Document/DocumentFragment/CharacterData/DocumentType)。
    - 追加バッチ(同日): `css/cssom` +2 vendor — css-style-attribute-modifications 1/1、
      css-style-attr-decl-block 5/7。**インライン style declaration の write-back を CSSOM 準拠に**:
      最後のプロパティを消しても `style` 属性は空("")で残す(旧実装は空になると属性ごと削除。
      remove は removeAttribute のみ)。旧挙動を pin していた dommy 単体テスト2件も spec 準拠へ更新。
      残2 = 無変更時の mutation record 抑止(CSS 値検証/no-op 検出が必要)、base URL 変更反映。
    - 追加バッチ(同日): `the-input-element/input-list` 6/6 vendor — **`HTMLInputElement.list` 実装**
      (`list` 属性 id を解決し datalist なら返す、それ以外/不在は null)。
    - 追加バッチ(同日): `the-input-element/clone` 19/19 vendor — **フォームコントロールの cloning steps 実装**。
      input の dirty value(`@__value`/`@__raw_value`)・dirty checkedness(`@__checked`)・indeterminate は
      Ruby wrapper 上の状態で、`form.cloneNode(true)` は backend subtree を一括 clone するため子 input の
      clone_node が呼ばれず dirty 状態が伝播していなかった。`clone_node` が元 subtree と clone 先を並行 walk し
      各 live wrapper の cloning state を copy(adoptNode の reseat と同型の `collect_subtree_nodes` 再利用)。
      `__cloning_state__`/`__apply_cloning_state__` に応答する wrapper なら誰でも参加できる汎用機構
      (textarea/select への拡張は将来テスト次第で容易)。実ページ(Turbo/morph の form clone)に効く。
    - 残 gap(未 vendor / 未達、より大きい):
      - Document-createAttribute 22/36 — **名前検証の緩和**(WPT `productions.js` の valid_names は
        "0"/"invalid^Name"/"~" 等も valid = 空文字以外ほぼ全許容。`// XXX` マーク付きで spec 曖昧 +
        serialize 回帰リスク → 保留)。
      - ~~remove-unscopable の残3(before/after/replaceWith) — runtime `setAttribute("on*")` 未再コンパイル~~
        **完了(同日)**: `host_runtime.js` の setAttribute/removeAttribute shim が on* 属性の set/remove 時に
        boot と同じ scope で handler を同期コンパイル({element, form, document} + on* IDL setter 経由)。
        remove-unscopable 6/6 全 green。実ページ(setAttribute で onclick を張る/フレームワーク)に効く。
    - 追加バッチ(同日): forms +2 vendor — textarea/cloning-steps 2/2、button-validation 6/6。
      **textarea の dirty value を defaultValue と分離**(旧実装は backend "value" 属性に格納 →
      setAttribute("value") と衝突・defaultValue を汚染。raw value を wrapper flag に移し value= は子テキスト
      不変、cloning steps で複製)。**submit `<button>` を constraint validation 候補に**(willValidate true;
      reset/button/disabled/datalist-descendant は barred)。副次で form-validation-willValidate 70→71。
      残(未 vendor): textarea value-defaultValue-textContent 7/12(CRLF 正規化・textContent 系)、
      select-ask-for-reset(selectedness reset)、select-validity placeholder label、button-events(submit/reset)。
    - 追加バッチ(同日): **tabular-data 21ファイル vendor(~120 subtests、ほぼ全 green)** — table/tr/tbody/
      thead/tfoot/caption/td-th の DOM API(caption/createCaption/deleteCaption、tHead/tFoot/tBodies/
      createTBody、rows、insertRow/deleteRow、cells、insertCell/deleteCell、rowIndex/sectionRowIndex、
      cellIndex)は Dommy が既に完全準拠で未計測だった典型例(分母拡大)。唯一の実バグ = td/th cellIndex が
      closest("tr") で祖先 tr を見ていた(spec は直接の親 tr のみ)を修正。dl grouping も vendor。
    - 追加バッチ(同日): text-level/interactive/embedded +5 vendor — details 5/5、a.text getter/setter 各 6・5、
      Image-constructor 5/5、a-stringifier 7/11。実装: **HTMLAnchorElement stringifier**(String(a)=href)、
      **named constructor(Image/Audio/Option)の prototype を non-writable 化**(WebIDL)。
      残: a-stringifier の 4 = `toString.call(nonAnchor)` の WebIDL illegal-invocation brand check(host method の
      this ブランド検査は bridge 未対応)、details name-attribute 12/18(mutually exclusive details grouping)。
    - 追加バッチ(同日): dom-tree-accessors +5 vendor — document.head-01/02、getElementsByClassName-same、
      Document/Element getElementsByClassName-null-undef。**document.head 修正**(at_css 全ツリー・namespace 無視 →
      documentElement の直下 HTML-ns head child;readonly 化 = 代入で shadowing expando を作らない。
      `__js_set__` UNHANDLED は set trap で expando 化される点に注意)。
      残(fiddly、未 vendor): document.forms iteration(HTMLCollection の WebIDL 属性 length の列挙)、
      document.images の foreign(SVG)img 除外(namespace フィルタ)、base_href_*(base 要素の相対 URL 解決)、
      Document.body の frameset/body edge。
    - 追加バッチ(同日): form/fieldset/select DOM API **12ファイル vendor(~37 subtests、全 green)** —
      form.elements interfaces/nameditem/sameobject、form/fieldset checkValidity/willValidate/validity、
      HTMLOptionsCollection(add/namedItem)は準拠済み・未計測(分母拡大)。加えて **fieldset disabled 伝播を修正**:
      `<fieldset disabled>` 子孫の control(最初の legend 内を除く)は willValidate=false に(`:disabled` 側は既に
      対応済みだったが will_validate は control 自身の disabled しか見ていなかった。共有 helper
      `disabled_by_ancestor_fieldset?` を HTMLElement に追加、input/select/textarea/button の will_validate に配線)。
      残: form-elements-filter(shadow tree scope)、disabled propagation の IDL `.disabled` 反映は別途。
      - ParentNode-querySelector-escapes 47/68(サロゲート、Ruby UTF-8 制約)、
        processing-instruction-attributes 0/140(PI 属性、非対応)、importNode の Attr 越境 clone、
        Node-properties 710/726(XML 文書 childNodes)。
  - [ ] その他各 1〜8 件: var-parsing 5、Text/Comment-constructor 各4、XMLSerializer 2 など

## 戦線B: 分母の拡大 (jsdom / happy-dom 対抗の本丸)

- [ ] **B1. 実装済み・未計測領域の vendor** — ⚠️ **「テストを持ってくるだけ」ではなかった (probe 済み 2026-07-05)**
  - 6 ファイルを probe した結果: shadow-dom **12/21 (57%)**、custom-elements **23→30/95 (32%)**。
    dommy 側の機能は実装済みでも **quickjs ブリッジの API 公開にギャップ**がある = 専用の hardening
    パスが必要 (単なる vendor では緑にならない)。probe ファイルはコミットせず撤去 (代表性のない
    partial vendor で headline % を汚さないため)。
  - **判明したギャップ (優先度順)**:
    - custom-elements: `attributeChangedCallback` の 4th 引数 namespace 欠落 → **修正済み (+7)**
      (下記)。残り: setAttributeNS/setAttributeNode の namespace 伝播、upgrade 時の enqueue、
      observedAttributes の再読取り、createElement の Construct 結果型チェック (TypeError)。
    - shadow-dom: `Element.prototype.shadowRoot` 未公開、`attachShadow` の二重呼び出し
      NotSupportedError、`ShadowRoot.activeElement` / `.styleSheets` 未実装。
  - **✅ 修正済み: `attributeChangedCallback(name, old, new, namespace)`** — dommy が 3 引数しか
    渡さず、WPT ヘルパーが `getAttributeNS(undefined, name)`→null で落ちていた。`mutation_coordinator`
    が arity を見て 4 引数対応コールバック (JS ブリッジ) に namespace を渡すよう修正 (3 引数 Ruby
    コールバックは後方互換維持)。custom-elements 23→30/95。
  - **✅ 修正済み: `attachShadow` のエラー型を spec 準拠に** — 無効な `mode` 値は WebIDL enum なので
    `TypeError` (旧 SyntaxError)、二重 attachShadow は `NotSupportedError` (旧 InvalidStateError)。
    dommy の既存テスト (旧挙動を assert していた 5 箇所) も spec に合わせて更新。attachShadow 2→3/6。
  - **✅ B1 installment 1 — interface prototype への member seeding (2026-07-11)**: ブリッジは DOM
    メンバをインスタンスの Proxy trap でしか応答せず interface prototype が空(`constructor` のみ)→
    `'attachShadow' in Element.prototype` / `Object.getOwnPropertyDescriptor(Node.prototype,'appendChild')`
    / `Element.prototype.getAttribute.call(el)` が全滅していた。curated な per-interface WebIDL member map
    (`INTERFACE_MEMBERS`)を追加し、`protoForChain` で各 prototype に delegating stub を seed
    (operation=関数 / readonly attribute=getter、`this` の handle 経由で host へ委譲、instance access は
    従来通り proxy trap)。**所有 interface に正しく配置**(appendChild=Node、getAttribute=Element、
    addEventListener=EventTarget = Dommy の Ruby class 構造でなく WebIDL 基準)。read-write reflected
    attribute は proxy set trap の cache 無効化を bypass するため据え置き(instance access は無傷)。
    さらに `attachShadow` の mode 欠如/不正を `Bridge::TypeError`(→ JS TypeError)化。
    → **shadow-dom `Element-interface-attachShadow` 6/6・`shadowRoot-attribute` 3/3 vendor**。
  - **✅ B1 installment 2 — ShadowRoot / Slottable (2026-07-11)**: `ShadowRoot.activeElement`
    (focused element を shadow tree に retarget、未接続/無 focus で null)+ `ShadowRoot.styleSheets`
    (shadow tree 内の `<style>`/`<link>` sheets、未接続で空)+ `Text.assignedSlot`(Slottable mixin、
    親要素 shadow tree の default slot、closed で null)。→ **shadow-dom `ShadowRoot-interface` 10/12
    (残 2 = 未接続 `<style>.sheet` が null — CSS cascade を壊さず条件化できず据え置き)・`Slottable-mixin`
    4/4 vendor**。
  - **✅ B1 installment 3 — CustomElementRegistry / define (2026-07-11)**: `customElements` は
    interface object 無し・validation 無しの plain JS object だった。`CustomElementRegistry` を実 interface
    として露出(operation を prototype に、`customElements` をそのインスタンス化)し、`define` を WHATWG
    準拠に再実装: IsConstructor / 名前(SyntaxError)/ 重複名・重複 constructor(NotSupportedError)/
    definition-running flag を spec 順で、flag 下で prototype(非 object→TypeError)→ lifecycle callbacks →
    observedAttributes(attributeChangedCallback 時のみ)→ disabledFeatures → formAssociated → form callbacks
    を順に読む。observedAttributes/disabledFeatures は **strict `sequence<DOMString>` 変換**(非 iterable で
    TypeError、`Array.from` の silent [] を回避)。`whenDefined` は同一 promise キャッシュ + define で解決。
    → **custom-elements/CustomElementRegistry 14→43/46**(残 3 = cross-realm running flag / 微細な
    property-access 順序 / upgrade の shadow-including tree order)。
  - **✅ B1 installment 4 — read-write reflected attribute の prototype accessor (2026-07-11)**:
    `Element.prototype.id`(/className/slot/innerHTML/outerHTML/title/…)を getter+setter accessor として
    seed。prototype setter は proxy set trap を踏襲([LegacyNullToEmptyString] coercion + DOM-epoch
    invalidation + setter 例外 re-throw)— set trap は instance write(`el.id=x`)を prototype setter に
    委譲するため、素の setter だと cache 無効化を skip して getAttribute が stale になる(初回 defer の理由)。
    → `'id' in Element.prototype` / `getOwnPropertyDescriptor` が正しく getter+setter を返す。回帰ゼロ。
  - [ ] **B1 残**: 残りの interface の member map 拡充、**custom-elements の construction invariants**
    (createElement で新規作成した空要素は ctor が attribute/children/挿入を追加不可 = NotSupportedError、
    非 node 戻り値 = TypeError。createElement と parse-upgrade の分離 + safe attribute reads が必要な
    hot-path 改修 — 専用設計要)、observedAttributes reflection / reactions、他 shadow-dom/custom-elements
    ファイルの vendor。
  - [ ] WPT `custom-elements/` ディレクトリ (要ブリッジ hardening)
- [~] **B2. html/ コーパスの拡大** — 現状 151 サブテストのみで 84.1%。フォーム要素・
  semantics 系を段階的に vendor し、穴埋めとセットで回す
  - **✅ forms hardening** — option (`defaultSelected`/`selected` の分離、`Option()` legacy
    ctor が spec 準拠に = 4引数目のみ selected を立てる)、textarea、input (file input の
    `value=` が非空で `InvalidStateError` を throw)、form、label + `RadioNodeList` /
    `HTMLFormControlsCollection`(名前衝突で複数一致→RadioNodeList、`.value` = checked radio)
    + `DOMException` legacy 定数 (`INVALID_STATE_ERR` 等) を interface に seed。
  - **✅ the-details-element toggle** (details.html 5/5, toggleEvent.html 9/11) —
    `<details>` の open 変化で **非同期 coalesced ToggleEvent** を dispatch
    (WHATWG「queue a details toggle event task」: 連続変化は 1 イベントに畳み、
    oldState=最初の変化前 / newState=最後の変化後)。`ToggleEvent` interface
    (`oldState`/`newState`, BASE_CHAINS seed) 追加、isTrusted 付与。Stimulus の
    `:open` アクションが依存。残り 2 = parser 生成 `<details open>` の load 時発火
    (harness 制約)。
  - **✅ the-form-element 名前付きゲッター** (form-nameditem 16/17, form-elements-* 全 green,
    dir 25/26) — (1) `form.elements` を **form-owner アルゴリズム**基準に再実装
    (`form=id` 属性 override + nested form の nearest-ancestor、DOM 子孫ではない;
    `object` も listed control に追加)、(2) HTMLFormElement を bridge の
    **[LegacyOverrideBuiltIns]** 対応に (NAMED_PROP_COLLECTIONS + get trap で
    named control が prototype method/accessor を shadow、getOwnPropertyDescriptor で
    named prop の descriptor を返す)、(3) **live RadioNodeList** (compute block で
    membership を都度再評価、削除を反映しつつ per-name memo で [SameObject])、
    (4) RadioNodeList を ARRAY_LIKE_COLLECTIONS に追加 (`i in list` / assert_array_equals)、
    (5) HTMLCollection の array-index を **canonical decimal** 判定に ("03" は named)。
    残り 1 = past-names map (rename/削除された control の記憶、stateful)。
  - **✅ the-fieldset-element** (7/7, 4 files 全 green) — fieldset は constraint
    validation から barred: `willValidate=false` + `checkValidity`/`reportValidity`
    を js_methods で公開 (常に true)。
  - **✅ the-button-element** (4/4 全 green) — `autofocus` reflect、`checkValidity`/
    `reportValidity`/`setCustomValidity` を公開、`labels` を labelable ヘルパーに移行。
  - **✅ the-output-element** (2/2 全 green) — value-mode-flag モデルで `value`/
    `defaultValue` を分離 (value= で mode を "value" に、以後 defaultValue= は
    textContent を触らない)、validity API (`setCustomValidity`/customError/
    `validationMessage=""`/`willValidate=false`)。`:valid`/`:invalid` は既に非マッチ。
  - **✅ labelable `labels`** — button/input/textarea/output 等で共有の
    `labels_node_list` を HTMLElement に追加: `for=` に加え **label 内包**
    (label.control = 最初の labelable 子孫) も拾う。nested/ancestor label 対応。
  - **✅ the-select-element (indexed interface)** (23/23 全 green) — HTMLSelectElement
    に **WebIDL indexed getter/setter + length= + item/namedItem**、
    HTMLOptionsCollection に **indexed setter アルゴリズム** (null で削除 / 範囲内で
    置換 / 末尾で追加+gap を blank option で pad)。bridge に **INDEXED_SETTER_INTERFACES**
    (`obj[i]=v` を host __js_set__ へ経路づけ) を追加、select/options を ARRAY_LIKE に。
  - **✅ harness BOM 修正** — WPT ファイル先頭の UTF-8 BOM を page_for で除去
    (BOM が doctype 前にあると HTML パーサが崩れ subtests 0 になる問題; select common
    3 ファイルが 0→全 green に)。
  - **✅ labelable `labels` の live 化** (labelable-elements 25→26/26, the-label 26/26,
    the-textarea 11/11) — `labels` を **memoized LiveNodeList** に: input が hidden に
    変わると保持中の NodeList が空になり (live)、型を戻すと同一オブジェクト
    ([SameObject]) を返す。testdriver 依存 (send_keys/click) の 2 ファイルは drop。
  - **✅ the-meter-element (62/62) + the-progress-element (16/16 全 green)** — WHATWG の
    「actual value」制約アルゴリズムを実装: meter は min→max(≥min)→value(∈[min,max])→
    low→high(∈[low,max])→optimum の順にクランプ、IDL setter は **restricted double**
    (`meter.value="foobar"` は ToNumber→NaN で TypeError)。progress は max≤0→既定1、
    value は indeterminate/invalid で **0**・[0,max] クランプ、`max=` は非正値を無視、
    position は determinate のみ value/max (indeterminate は -1)。labels も live 化。
  - **✅ the-a-element text** (a.text-getter 6/6, a.text-setter 5/5) — `a.text`
    getter/setter (= descendant text content)。grouping-dl も vendor (1/1)。
    a-stringifier は WebIDL stringifier branding が必要で drop。
  - **✅ the-dialog-element (close/open) + イベント this バインディング** (dialog-close 5/5,
    dialog-close-event(-async) 各 1/1, dialog-open 3/3) — (1) `close()` は open 属性が
    無ければ abort、あれば **非同期 trusted close イベント**を queue、(2) `showModal()` は
    open 済み / 非接続で **InvalidStateError**、(3) **イベントリスナの `this` を
    currentTarget に**バインド (CallableInvoker → HostCallback#__js_call_with_this__;
    従来は undefined→global だった)。dom/events 91/91 維持。showModal の focus/top-layer
    系と canceling (testdriver) は drop。
  - **✅ the-time-element** (8/8 全 green、dateTime reflection、コード変更不要)。
  - **✅ details name-group 排他制御** (name-attribute 2→12/18) — `<details name>` の
    相互排他アコーディオン: 名前付き details が開くと同じ (name, tree scope) の他の
    open な details を閉じる (`get_root_node` で scope 解決)。name 属性変更時も再適用。
    残りは parser-time 適用 / mutation ordering / disconnected tree の edge cases。
  - **✅ the-input-element radio-group + selection** (radio 10→12/12, selection 27→42/42) —
    (1) ラジオグループを **tree scope (`get_root_node`) + form owner** で解決 (orphan tree /
    `form=` 属性 / 異なる form owner を正しく分離)、(2) `valueMissing` を **グループの
    checkedness** 基準に (runtime `.checked` 使用)、(3) **text selection API**
    (selectionStart/End/Direction + setSelectionRange + select): 対応型
    (text/search/url/tel/password) 以外は getter null・setter は InvalidStateError。
    change/defaultValue/email-set-value は testdriver 依存で drop。
  - **✅ the-input-element valueAsNumber + stepUp/stepDown** (valueasnumber 64/64,
    stepup 53/53, stepdown 5/5 全 green) — 7 型すべての **数値⇄文字列変換**を実装:
    number/range (Float + range クランプ)、date/datetime-local/time/week (UTC ms)、
    month (1970-01 からの月数)。stepUp/stepDown は **型別の default step**
    (time/datetime-local=60s) と **step scale factor**、min/max クランプ +
    step-base アラインメント、非対応型/step="any" で InvalidStateError、
    クランプが step 方向に逆行しない保証。`require "date"` を追加。
  - **✅ constraint validation (forms/constraints)** (192→249/265, 94%) — ValidityState の
    rangeUnderflow/rangeOverflow/stepMismatch を **`value_as_number` ベース**に再実装
    (全 7 型で min/max/step 比較)、valueMissing を date 型で「値が parse 不能 =欠落」に、
    **disabled/readonly は valueMissing のみ barred** (rangeOverflow 等は barred されない、
    per spec)、datetime-local パーサに space 区切り許容。valueMissing 45→71/78、
    rangeOverflow 47/49、rangeUnderflow 46/47。valueAsDate は Date の双方向 marshaling が
    必要で先送り。`support/validator.js` も vendor。
  - **✅ constraint validation 続き** (constraints 全体 **655/684, 95.8%**) —
    **checkValidity/reportValidity 各 130/130 全 green**、typeMismatch 11/11
    (WHATWG email 正規表現 + `multiple` のカンマ区切り検証)、patternMismatch 74/85
    (pattern を **単独で妥当性検証**してから anchor: `a)(b` の unbalanced を弾く)。
    残りは JS `v`-mode 正規表現セマンティクス (Ruby 非対応)。stale な 404 fixture も掃除。
  - **✅ constraint validation 詰め** (constraints 649→**667/684, 97.5%**) —
    **tooLong/tooShort は user edit 時のみ発火**(script 代入では常に false; spec の
    「値が user edit で変更された」条件)、valueMissing **78/78 全 green**:
    number の **strict valid-float 判定**(" 123 " や whitespace は NaN)、checkbox/radio/
    select は disabled でも flag が立つ(barred は willValidate のみ、text-like のみ mutability
    要件)、**unnamed radio は非 missing**、**detached radio の group に self を含める**
    (query_selector_all は自身を返さない)、file は files.length==0、select は placeholder
    (空 value)選択で missing。さらに **reversed time range**(min>max の周期領域: 除外ギャップで
    rangeOverflow/Underflow 両方 true)で rangeOverflow **49/49** + rangeUnderflow **47/47**、
    week の **step base を 1970-W01** に(epoch は週の途中)で stepMismatch 27/28。
    constraints 全体 **672/684 (98.2%)**。残 12 = JS `v`-mode 正規表現(11)+ 極小 float step 精度(1)。
  - **✅ tabular-data/the-table-element** (42→**60/60 全 green**) — caption/thead/tfoot/tbody/rows を
    **HTML 名前空間フィルタ**に (SVG の同名要素を除外)、deleteRow に境界チェック
    (IndexSizeError) + `-1`=末尾、`tHead=`/`tFoot=` setter (非セクション→TypeError、
    誤ローカル名→HierarchyRequestError)、caption setter の型検査、void メソッドは
    undefined を返す。さらに caption/section 挿入を生 backend から **検証済み
    insert_before/append_child** 経由に変更(`ensure_pre_insertion_validity!` で
    cycle→HierarchyRequestError、`detach_dom_nodes`→adopt_node で異 document adoption)、
    `rows` を **tree order** に修正(直下 `<tr>` と tbody 行を文書順にインターリーブ)。
  - **✅ the-tr-element (45/45) + the-tbody-element (13/13) 全 green** — cells/insertCell/
    deleteCell/rowIndex/sectionRowIndex/insertRow/deleteRow を実装: 境界チェック
    (IndexSizeError) + `-1`=末尾、rowIndex は HTMLTableElement 祖先のみ、sectionRowIndex は
    親が table/thead/tbody/tfoot の HTML 要素のときの行 index。**namespace 判定を strict 化**
    (`createElementNS("","table")` 等の null 名前空間を HTML 扱いしない; 従来 nil を HTML と
    誤判定していた)。section include (`html-table-section-element.js`) も vendor。
  - **✅ the-template-element** (template-content **216/216**, template-as-a-descendant 12/12,
    content-attribute 5/7) — `template.content` を bridge の **READONLY_ATTRS** に追加
    (getter-only アクセサ、assert_readonly 対応)。`html/resources/common.js` を vendor して
    多数の template テストを解放。残りは newHTMLDocument / iframe contentWindow 依存。
  - **✅ the-option-element (44/44) + the-datalist-element (2/2) 全 green** — option の
    **selectedness/dirtiness モデルを spec 準拠に**再実装(getter は selectedness を直接返す、
    `selected` 属性変化は非 dirty 時のみ同期、`__internal_set_selectedness__`)、Option
    コンストラクタを **JS truthiness**(0/""/NaN を falsy)+ 4番目引数の非 dirty 設定に、
    `label`/`value` を **null 名前空間属性のみ**反映(setAttributeNS の別名前空間 label は無視)、
    `option.text` の script/style 除外を HTML/SVG 名前空間のみに、datalist 祖先を持つ
    select/textarea/input を **willValidate=false**(barred)に。
  - **✅ the-select-element selectedness** (dir **42/42 全 green**) — selectedIndex/value/
    selectedOptions を **runtime selectedness** ベースの display-time 計算に:単一選択は
    最も新しく property-選択された option が勝ち(dirty > attribute)、無ければ最初の option
    (ask-for-reset)、複数選択は全 selected。selectedOptions を **[SameObject]** memo 化、
    `options.add(opt, index)` を **reference の親**(optgroup 可)に挿入。inserted-or-removed
    5/5・option-selectedness-script-mutation 5/5・selectedOptions 8/8。
- [~] **B3. fetch / xhr / FileAPI / streams / storage / websockets / urlpattern の vendor**
  - 実装は既に存在する (Lilac 監査でギャップ僅少)。計測して穴を潰す
  - **✅ webstorage vendor + hardening (1172/1200, 97.7%, 10/12 files green)** — Storage を
    WebIDL legacy platform object 準拠に: (1) DOMString 強制 (getItem/setItem/removeItem の
    null→"null"/undefined→"undefined"、値 ToString)、(2) `key()` の ToUint32 (2**32 wrap)、
    (3) 引数不足→TypeError、(4) named-property 列挙/deleter (`Object.keys`/`for…in`/`delete
    storage[k]` = 保存キーのみ、builtins 非列挙)、(5) named setter の値 ToString を JS 側で、
    (6) `Object.defineProperty(storage,k,{value})` を named setter へ経路づけ、(7) **WebIDL
    named-property 可視性** (prototype に同名プロパティがあれば named prop を隠す=no
    LegacyOverrideBuiltIns) を bridge の get/ownKeys/getOwnPropertyDescriptor/set に実装。
    残り28 = lone-surrogate 往復 (Ruby UTF-8 で表現不能, ~24)・prototype-seeding
    (`Storage.prototype.getItem` の関数 identity, 2)・throwing-toString の method 引数 (2)。
  - **✅ FileAPI/blob vendor + Blob hardening (256/260, 98.5%, 7/8 files green)** — (1) `bytes()`
    実装 (Promise<Uint8Array>)、(2) `new Blob(undefined)` を空 Blob に (旧: "undefined" 9 bytes)、
    (3) **`sequence<BlobPart>` 変換を JS 側 `coerceConstructorArgs` で** (primitive→TypeError、
    String オブジェクト/@@iterator plain object を iterate、ArrayBuffer/TypedArray/DataView→bytes、
    Blob 透過、それ以外 USVString)、(4) `BlobPropertyBag` の endings enum 検証+getter 副作用+
    native 改行正規化、(5) `type` の charset gate (U+0020..U+007E 外→"") を Blob#initialize に
    (slice contentType にも適用)、(6) `slice` の `[Clamp] long long` 丸め (banker's rounding) +
    undefined 引数の既定値化 + null contentType→"null"。残り4 = `stream()` 未実装 (1)・
    Blob-constructor の getter/length アクセス順エッジ (3)。
  - **✅ fetch vendor + WPT サーバ基盤 + CORS 実装 (fetch/api 316+ subtests, 15 files, 大半 green)** —
    「要サーバ」を **`Dommy::Resources` の上に WPT エンドポイント emulation** を載せて解決:
    - **エンドポイント基盤** (`test/support/wpt_endpoints.rb`): `status.py` / `inspect-headers.py` /
      `redirect.py` / `redirect-empty-location.py` / `preflight.py` / `clean-stash.py` を
      `#request(method,url,headers,body)→Response|nil` の Resources アダプタとして実装。
      `?pipe=header(…)|status(…)` ラッパ (`WptPipe`)、`.sub` テンプレート置換
      (`{{host}}`/`{{ports[…]}}` → 単一ホストで別ポート=cross-origin)、token 別 **stash**
      (preflight 記録) を追加。`Browser` が `__fetch_handler__ = FetchHandler.new(resources)` を
      既に配線済みなので追加配線ゼロ。
    - **fetch polyfill 強化** (dommy `fetch.rb`): Request の body 消費メソッド (text/json/
      arrayBuffer/blob/bytes)、WHATWG UTF-8 decode (BOM 除去+scrub)、デフォルトリクエストヘッダ
      (Accept/Accept-Language/User-Agent/Origin/Content-Length、case 保持)、**リダイレクト追従**
      (follow/manual/error、303→GET、opaqueredirect、空/data Location=network error)、
      reject を real `Bridge::TypeError` に、**CORS** (same-origin/no-cors→opaque/cors→ACAO 検査/
      preflight OPTIONS→ACAM・ACAH 検査/credentials→ACAC+`*`無効/レスポンスヘッダフィルタ)。
    - **重要な回帰対応**: CORS 強制は **handler(サーバ)由来のみ**適用し **stub/data: は免除**
      (`__fetchy_stub__` の cross-origin fetch=実アプリ/既存テストの一般パターンを壊さない)。
    - **bridge 修正**: maplike の `entries()/keys()/values()` を live iterator 化
      (`headers.entries().next()` の "not a function" 解消)。
    - green: text-utf8 30/30・accept-header 4/4・request-headers 25/25・mode-same-origin 8/8・
      mode-no-cors 4/4・cors-basic 15/15・cors-no-preflight 15/15・cors-preflight 22/22・
      cors-preflight-status 27/27・cors-multiple-origins 6/6・redirect-location 55/55・
      redirect-empty-location 2/2。partial: cors-preflight-star 28/34・cors-filtering 12/19・
      cors-origin 9/17・cors-expose-star 2/3。
    - 残り (深いテール): CORS+redirect の Origin=null tainting、preflight response validation、
      credential×expose の相互作用、stateful redirect-count、cross-origin の実マルチオリジン。
  - **✅ xhr vendor + XMLHttpRequest hardening (180/199, 90.5%, 11/12 files green)** — 同じ
    エンドポイント基盤を XHR に横展開:
    - **重要な発見**: `XMLHttpRequest.HEADERS_RECEIVED`/`DONE` 等の **readyState 定数が
      コンストラクタに未 seed**(instance には有り)→ `if (xhr.readyState === XMLHttpRequest.DONE)`
      が永久 false → **全 async XHR テストが timeout**。`INTERFACE_CONSTANTS` に seed して解消。
    - **エコーエンドポイント** `content.py`(request body エコー)+ `echo-content-type.py` を追加 →
      **send-usp 1→129/129** ほか send 系が一気に green。
    - XHR hardening (dommy `xml_http_request.rb`): send() の **body 抽出**
      (`Response.extract_body` で ArrayBuffer/TypedArray/Blob/URLSearchParams/FormData → bytes)+
      デフォルト Content-Type、二重 send → InvalidStateError(send フラグ)、responseType 状態検証
      (sync-in-window / loading・done → InvalidStateError)、async 404 を network task で配信、
      responseType "json" の WHATWG parse JSON from bytes(UTF-8 decode + BOM 除去)。
    - green: send-usp 129/129・send-data(string-invalid-unicode 9/9 / arraybuffer / arraybufferview)・
      event(load/loadstart/loadend/readystate-sync-open)・content-type-unmodified・send-send・json。
      partial: responsetype 31/50(Document responseType・sync-flag エッジ)。
    - 残り: upload progress イベント、timeout、blob: URL、streaming エラー、Document responseType、
      overrideMimeType、send(ES object) の JS 側 ToString。
  - 未着手: urlpattern は URLPattern 未実装、streams は大規模。
- [ ] **B4. ブリッジのバッチ化 → reflection.js の解放** — 互換計測と実アプリ性能の一石二鳥
  - **✅ B4 initial installment (2026-07-14, dommy fc1af56)** — D4b の実データ駆動で 3 点:
    (1) expando write の JS 側化 (own-prop 短絡 + host が一度 decline した (interface, prop) の
    負キャッシュ。on*/window は value 依存なので除外)、(2) Attr#name 等を interface 別 const
    キャッシュ + Attr#value を epoch キャッシュ、(3) createElement/cloneNode 等の factory を
    非変異に分類 (detached 生成はキャッシュを stale にできない) + isConnected を epoch-stable に。
    **実測**: React initial 124.8→91.3ms (-27%)、re-render 53.9→34.4ms (-36%)、morph 405→339ms
    (-16%)。全 5 スイート green。
  - **検討して見送り: JS 側 epoch の attr/tree 分割** (Ruby 側 D1b の bridge 版) — morph の
    支配項 dispatchEvent は Ruby 側デフォルトアクション (details の open 属性等) が DOM を
    変えうるため保守バンプが必須で、分割しても効果が薄い。イベントの JS 側化とセットで再検討。
  - **✅ B4 installment 2 (2026-07-14, dommy 9704b6c): unlistened-dispatch fast path** —
    設計 `docs/event-dispatch-fastpath.md`。判定と実行を 1 往復に融合した
    `__rb_host_dispatch_fast`: type がコロン入り (組み込み default action なし) かつ
    EventTarget の**追加専用** type レジストリ (Ruby が権威 = 同期問題が構造的に無い) で
    未リッスンなら通常 dispatch を実行し、JS 側は epoch バンプをスキップ +
    defaultPrevented を own-prop shadow 化 (preventDefault/initEvent/returnValue/再dispatch で
    shadow 整合)。**実測**: morph 405→~330ms、51905→41081 越境 (D4b 基準から累積 -19%/-21%)。
    エッジテスト 9 本追加、全 5 スイート green。
  - **調査して見送り: NamedNodeMap の読み取りバッチ RPC** — Ruby 側の NamedNodeMap/Attr
    ラッパーは identity 安定 (item(0).equal?(item(0)) == true) で proxy の const キャッシュは
    既に効いている。morph 残の Attr#name ~1800 は「fetch した新文書側 + setAttribute で
    再生成された Attr」の初回読みでキャッシュ不能。facade 化は WPT の identity 意味論を
    壊すリスクの割に効果が薄い。conformance 再計測: **49186/49481 (99.4%) / 710 files
    (639 fully green)** — 本日のブリッジ変更 (fc1af56 / 9704b6c) で退行なし。
  - **残 (Stage 2): イベントオブジェクトの JS 側化** — construct 側の残 1514 越境。
    slow path でリスナーが受ける event の同一性 (e === ev) を保つには JS event を正とする
    反転が必要 (bridge-redesign.md 領域)。
  - `html/dom/reflection-*.html` (数千サブテスト) は全 DOM 操作が Ruby 往復するため
    60 秒 VM タイムアウトで vendor 不能
  - [ ] (a) 単純な属性 reflection の getter/setter を定義テーブルから JS 側で生成し、
        往復を属性 read/write に集約
  - [ ] (b) DOM epoch キャッシュの拡張 (既存の attribute snapshot キャッシュを一般化)
  - [ ] (c) 読み取り系のバッチ RPC
  - [ ] 完了後に reflection-*.html を vendor して計測
  - Turbo morphing / React render の性能に直結するので、前後でベンチマークを取る

## 戦線C: 実アプリ互換 (利用者が実際に比較する軸)

- [~] **C1. イベントループの JS 側集約** — **skip(quickjs.rb 側の問題)**
  - unhandled rejection の誤検知は切り分けの結果 **quickjs.rb の C バインディング**
    (`HostPromiseRejectionTracker` が reject 即時に eager 報告)が原因で、dommy 側の
    修正余地なし。**quickjs.rb に修正ブランチ `fix/unhandled-rejection-checkpoint-timing`
    が既に存在**(commit 775e81a: microtask checkpoint 終端で報告)。gem がリリース→dommy が
    上げれば dommy 側変更ゼロで解消。dommy 側では対応しない。
- [~] **C2. フレームワーク公式テストスイートを互換ベンチに** — Stimulus は完成済み
  - [x] Stimulus 公式 QUnit スイート: `rake stimulus:conformance` で **210/214 (98.1%)**。
    `StimulusConformance` + `stimulus-tests.umd.js`(`build_stimulus_tests.sh` で再生成)。
    残り 4 = ApplicationStartTests 0/3 (document loading 状態) + LegacyTargetTests 9/10。
  - [~] Turbo 公式スイート: **unit のみ移植可**。`rake turbo:conformance` で **20/38 (52.6%)**。
    `TurboConformance` + `turbo-tests.umd.js`(`build_turbo_tests.sh` で再生成、mocha TDD +
    chai `assert` は `mocha_shim.js` / `@open-wc/testing` は `openwc_testing_shim.js` で供給)。
    完全 green: export/limited_set/native_adapter/deprecated_adapter (20/20)。残り
    `stream_element_tests` 18/18 = **`new StreamElement()`(カスタム要素の JS コンストラクタ直接
    呼び出し)未対応** — queued upgrade のない `super()` が `HTMLElement` を構築しようとし
    "Illegal constructor"。**B1 の custom-elements ブリッジ hardening 領域**(Construct 結果型
    チェック / upgrade enqueue)。なお同じ stream レンダリング挙動は
    `test_turbo_integration.rb`(44 本)が `renderStreamMessage` 経由で緑にカバー済み。
    Turbo の functional 26 + integration 1 は **Playwright + Koa サーバ + 実ページ間ナビゲーション
    依存で単一 VM 移植不可**(Stimulus の ApplicationStartTests と同じ壁)。その一部
    (pausable rendering/requests・`action="refresh"` stream)は `test_turbo_integration.rb` に
    手書きケースとして追加済み。
  - [ ] Lit 公式スイート(bundle は vendor 済みだが公式-suite runner は未)。
- [x] **C3. jsdom / happy-dom との同一コーパス比較表** — 完了
  - ランナー `script/wpt-compare/`(Node、jsdom + happy-dom、プロセス分離)、レポート
    `docs/dom-library-comparison.md`。**245 ファイル中 fully-green: Dommy 192 / jsdom 122 /
    happy-dom 55**、完走 245/207/165。**確実な知見**: (1) happy-dom は classic script 間で
    トップレベル `class`/`const`/`var` を共有しない(ブラウザ非互換、独立検証済み)、(2) ARIA
    computed role/label は Dommy 独自(happy-dom も jsdom も 0)。**Dommy の実ギャップ** = jsdom が
    green で Dommy not の 10 ファイル(dom/nodes + abort 中心)= 確実に取れる宿題。

## 戦線D: 高速化 (conformance と並走)

2026-07-05 のマイクロベンチ実測 (N=2000、小 DOM、scratchpad/bridge_bench.rb 相当):

```
JS plain prop read                 0.04 us/op   (ブリッジなしの下限)
JS→Ruby getAttribute (snapshot)    0.49 us/op   ← 属性スナップショットキャッシュが効いている
JS→Ruby el.id read                 1.27 us/op   ← 一般プロパティ read は毎回往復
JS→Ruby textContent read           1.41 us/op
JS→Ruby setAttribute               4.55 us/op   (Ruby 直: 1.08 us)
JS→Ruby querySelector             11.2  us/op   (Ruby 直: 1.08 us) ← 往復+結果ラップが支配的
JS→Ruby create+append+remove      31.2  us/op   (Ruby 直: 11.9 us)
VM boot (BrowserHarness)           3.6  ms
todo-app browser spec median      40 ms (UMD) → 62 ms (ESM)  ← モジュール再パースの回帰
```

計測ツール: `DOMMY_JS_BRIDGE_PROFILE=1` (往復回数の Interface#member 別集計、
`Runtime#bridge_crossing_counts`)、todo-app `script/benchmark_specs.rb` /
`benchmark_browser.rb` (`BENCH_RUNS`/`BENCH_N`)、makiri `rake bench`。
crossing timeout 除去 (property read 9.8→5.1us) は導入済み・デフォルト off 維持。

### D1. Dommy core (Ruby 層) — 安価で広く効く順

- [x] **D1a. セレクタ AST のグローバルキャッシュ** — 完了
  - `SelectorParser.parse!` に `(selector, namespaces)` キーの module 級キャッシュを追加
    (`AST_CACHE_CAP=2048`、generation タグなし、無効セレクタは SyntaxError を記録し再 raise)。
  - **実測 (N=2000, best-of-3)**: `matches?` 14.73→1.74 us/op (**8.5x**)、
    mutate+querySelector 26.11→7.94 us/op (**3.3x**)。conformance 回帰ゼロ (全 245 ファイル一致)。
- [x] **D1b. style_generation エポックの分割** — 完了 (2026-07-14)
  - `dom_generation` (セレクタ結果キャッシュ: query cache / scoped query / selector index) と
    `style_generation` (cascade キャッシュ: RuleIndex / computed / counters) に分離。
    childList は両方 bump。attribute は dom は常時、style は RuleIndex が selector AST から
    収集した属性依存集合に載る時のみ ("style" は常時、pseudo-class は静的マップ、
    :valid/:invalid など未マップ構文は all-attrs へ保守フォールバック、<style>/<link> の属性は常時)。
    characterData は「空⇄非空の反転」(:empty が matcher 唯一のテキスト依存) で dom を、
    反転かつシートが :empty 使用時と <style> 祖先内のみ style を bump。
    focus/hover/checked= 等のセレクタ可観測状態は両方 bump (旧単一カウンタと同等の正しさを維持)。
  - **実測 (300 要素 × 100 ルール, N=500, best-of-3)**: characterData+computed 65083→5.3 us/op、
    data-\*+computed 65989→4.6 us/op (**~14000x**)。正当な無効化 (class 変更 66432→63592 us/op、
    data-\*+querySelector 634→649 us/op) は不変。characterData+querySelector 638→2.5 us/op。
    回帰ゼロ (dommy 3416 [新規 invalidation 16 含む] / rack 232 / rails 71 / capybara 1259 /
    quickjs 788 全 green)。bench: dommy `benchmark/cascade_invalidation_benchmark.rb`。
- [x] **D1c. MutationCoordinator のゲーティング** — 完了
  - (1) **connected/disconnected subtree walk を target の接続性でゲート**: detached な
    subtree への変更 (bulk 構築) では connectedCallback / script / blank-iframe load の
    どれも発火し得ないので O(subtree) walk を丸ごとスキップ (script/iframe は元々
    is_connected? gate 済み、connectedCallback も spec 上 connected 時のみ)。attach 時に
    subtree 全体へ発火するのは従来通り。副次的に「detached 追加で connectedCallback が
    誤発火する」既存バグも解消。
  - (2) **observer ゼロなら record 構築をスキップ**: `ObserverManager#any?` を追加し、
    wrapped_added/removed の eager wrap + MutationRecord + observer ループを丸ごと省略。
  - **実測 (pure-Ruby, detached bulk build, N=20000, best-of-3)**: 631.6→487.4 ms
    (**23% 高速化**、31.58→24.37 us/node)。ブリッジ経由シナリオは crossing コストが支配的で
    ~9%。回帰ゼロ (dommy 3338 + quickjs 593 green)。bench: `script/bench_bridge.rb` の
    「detached bulk build + attach」ケース。
- [x] **D1f. RuleIndex の逆引き化 (lazy rule hash)** — 完了 (2026-07-14, D1b の続き)
  - 旧構造は build 時に全ルール × document 全体 query (rules -> elements の順引き) で、
    正当な無効化 (class 変更等) のたびに 63ms を再払いしていた。plain ルール (非 @scope /
    非 shadow / 非 ::part) を右端 compound の id > class > tag > universal でバケツ分けし
    (WebKit rule hash と同型)、`matches_for(element)` で要素側から候補を引いて lazy 照合 +
    要素別メモ化に変更。@scope / shadow / ::part のみ eager のまま。
    document シートのルールが shadow tree 内へ届かないゲート
    (`__internal_shadow_root_containing__`、shadow root ゼロなら skip) を追加。
  - 追加で: sheet テキストの parse cache (text 鍵, cap 64) と、`tree_generation`
    (childList のみで動く第3エポック) 鍵の style/link 要素リストメモ
    (`Document#__internal_style_sheet_elements__`) — 属性起因の再構築が document walk を払わない。
  - **実測 (300 要素 × 100 ルール, N=500, best-of-3)**: RuleIndex.build 63249→713 us/op (**89x**)、
    class setAttribute+computed_style 66432→959 us/op (**69x**)。読み取り床 ~3 us、
    characterData / data-\* + computed ~5 us は D1b から不変。
    回帰ゼロ (dommy 3416 / rack 232 / rails 71 / capybara 1259 / quickjs 788 全 green —
    shadow 境界の越境は test_css_shadow_scoping が検出し、ゲートで解消済み)。
- [x] **D1d. NodeWrapperCache ヒットパスの検証削減** — 完了 (2026-07-14)
  - `Dommy::Parser.fragment_generation` (プロセス全体の fragment parse カウンタ) を新設し、
    cache 生成時から動いていない間は per-hit の nodeType 検証 (C 往復) を丸ごと省略。
    identity 再利用には transient ノードの解放が必要で、transient は fragment parse からしか
    生まれないため。直接 `backend_doc.fragment(...)` していた 8 箇所を Parser.fragment 経由に
    一本化 (バイパス不能に)。fragment parse が一度でも起きたら従来の毎ヒット検証に戻る。
  - **実測**: Ruby create+append+remove 9.7→8.7 us/op、detached bulk 13.9→11.1 us/node、
    bridge create+append+remove 35.5→32.0 us/op。全 5 スイート green。
- [x] **D1e. matcher の属性二重読みの解消** — 完了 (2026-07-14)
  - fast_query / descendant walk で backend_passes? 済みの prefilter を `verified:` として
    matches_compound? に引き回し、その simple selector の属性再読 (C 往復) をスキップ。
    厳密等価な種別のみ (id / class / 裸の属性存在)。:type は大文字小文字の superset なので対象外。
  - 副産物の正修正: SelectorIndex の class 分割が /\s+/ (\v を含む) で class_tokens の
    ASCII 空白と不一致 → exact_class_or_id_prefilter が index を厳密一致として信頼していたのに
    実際は superset だった。ASCII 空白分割に統一。
  - **実測**: 属性 prefilter 系 query ~-5%、descendant 連鎖 ~-3%、他はノイズ内 (経路の支配項は
    index 再構築と wrap)。全 5 スイート green。

### D2. ブリッジ層 (B4 と同一投資 — conformance の reflection.js 解放と両取り)

- [x] **D2a. 属性 reflection の JS 側化** — 完了 (read パス)
  - `host_runtime.js` の get trap に `REFLECTED_STRING_ATTRS`(`id`/`className`→`class`/`slot`)を
    追加し、要素の属性スナップショット(getAttribute が使う既存キャッシュ)から回答 → 往復ゼロ。
    純粋な reflection(Ruby getter が `node[attr].to_s`、"" when absent)のみに限定し、
    coercion/default を持つ dir/tabIndex/boolean 系は対象外。非要素/foreign-ns は snapshot=null で
    従来通り host にフォールバック(`document.title` 等は無傷)。
  - **実測**: `el.id` 1.27→**0.39 us/op (~3.3x)**、`el.className` 0.36 us/op。挙動不変・
    conformance ドリフトゼロ(40173/40443 維持)・両スイート green。
  - **付随発見**: `el.title`/`el.lang` は現状 `undefined` を返す(reflection 未実装の潜在バグ)。
    D2a は挙動不変に保つため対象外。別途 Ruby 側 `__js_get__` に arm を足せば修正可(perf ではなく correctness)。
- [x] **D2b. epoch スナップショットキャッシュの一般化** — 完了
  - `host_runtime.js` に `STABLE_EPOCH_NODE_PROPS`(parentNode/parentElement/ownerDocument/
    firstChild/lastChild/next|previousSibling/next|previousElementSibling/first|lastElementChild/
    childElementCount/textContent)の per-epoch キャッシュを追加。tree-walk の反復読みが
    往復1回に畳まれる。epoch はミューテーション/Ruby→JS entry で bump するので stale にならない
    (createElement→appendChild→nextSibling が正しく更新されるのを検証済み)。
  - **実測**: nextSibling 10.6→**0.38 us/op (~28x)**、parentNode 2.5→0.37、textContent 1.4→0.38。
    挙動不変・conformance ドリフトゼロ(40173/40443、TreeWalker 760/761 維持)・両スイート green。
  - 残る高コストは `childNodes.length`/`children.length` (~12us) = live collection の proxy 化 +
    length 往復。collection を live に保つ必要があり D2c 領域。
- [~] **D2c. 読み取りバッチ RPC** (= B4c) — 一部完了 (collection length)、iteration は未
  - **✅ collection の `.length` を epoch キャッシュ**: live collection (childNodes=LiveNodeList、
    children=HTMLCollection、これらは proxy として渡る; 静的な querySelectorAll は `NodeList < Array`
    で JS 配列として渡り既にローカル) の `.length` を epoch キャッシュ + `.childNodes`/`.children`
    proxy 自体も epoch キャッシュ。**childNodes.length 12.7→0.59 us (~21x)**、children.length 同様。
    append/remove で 1→2→1 と正しく無効化されるのを検証済み。回帰ゼロ。
  - [ ] **残: indexed iteration のバッチ**。`children[i]`(~11us)/`Array.from(children)`(~18us/elem)は
    要素ごとに往復。`Array.prototype[Symbol.iterator]` が `this[i]` を読むため。設計: Ruby collection に
    bulk items アクセサ (`__js_items__` → to_a) を追加し、JS arrayLike proxy の indexed get を epoch
    キャッシュした items 配列から回答 (1往復)。**リスク**: live collection の正しさ (epoch 無効化で担保可)、
    非ノード collection (DOMTokenList=文字列, NamedNodeMap=Attr) の扱い、未対応 collection の
    フォールバック。cross-cutting なので独立に慎重設計が必要。
- [x] **D2d. querySelector 経由の 11us/call の内訳をプロファイル** — 完了
  - `DOMMY_JS_BRIDGE_PROFILE=1` の結果: querySelector は **1 呼び出し=往復1回のみ**(冗長往復なし)。
    11us は「クロッシング + 結果 element の proxy 化」という本質的マーシャリングコスト。安い削減余地なし
    → 結果 proxy のキャッシュ/バッチ (D2c) が必要。
- [ ] **D2e. 長寿命 VM のメモリ衛生** — callbacks Map / jsRefs テーブルの無限成長
  (bridge-redesign.md 残課題) に解放経路を付ける

### D3. VM 起動・スクリプトロード

- [ ] **D3a. ES モジュールのバイトコードキャッシュ** (`docs/module-bytecode-cache.md`)
  - 実測済みの回帰 40ms → 62ms/example (importmap/ESM 移行で ScriptCache が効かなくなった)
  - quickjs gem 側の `JS_WriteObject`/`JS_ReadObject` モジュール対応が本丸 (要 gem PR)、
    その後 ScriptCache にモジュール系統を追加
- [ ] **D3b. VM 初期化の固定費削減** — seedInterfaces + polyfill/alias の inline eval 群を
  バイトコード化 (host_runtime.js 本体は compiled_bundle 済みだが、これらは毎 VM 素の eval)。
  将来: heap snapshot (gem 機能待ち、優先度低 — 現状 VM boot 3.6ms は十分軽い)

### D4. 計測基盤 (最初にやる)

- [x] **D4a. ベンチマークの CI 固定化** — マイクロベンチ (往復コスト系) + todo-app
  `benchmark_specs.rb` median を記録し、回帰閾値を設ける。D1/D2 の各項目は
  before/after をこのベンチで示してからマージ
  - `script/bench_bridge.rb` を追加 (`bundle exec ruby script/bench_bridge.rb`、`N` で回数)。
  - **基準値 (2026-07-05, N=2000, Makiri backend, best-of-3)**:

    ```
    JS plain read (floor)                0.03 us/op
    JS->Ruby getAttribute                0.50
    JS->Ruby el.id / textContent         1.37
    JS->Ruby setAttribute                4.99
    JS->Ruby querySelector              11.34   (Ruby 直 0.40)
    JS->Ruby create+append+remove       32.12   (Ruby 直 9.20)
    Ruby matches?                       14.73   ← D1a 対象 (毎回 parse!)
    Ruby mutate+querySelector           26.11   ← D1a 対象 (generation バンプで再 parse)
    VM boot                              3.79 ms
    ```
  - D1a マージ時に `Ruby matches?` / `Ruby mutate+querySelector` の低下を併記する。
- [x] **D4b. 実アプリプロファイル 1 本** — 完了 (2026-07-14)
  - `script/profile_real_app.rb` を常設 (React 300行 render/re-render + Turbo 8 morph、
    `DOMMY_JS_BRIDGE_PROFILE=1` で phase 別の上位往復 + 実時間)。
  - **基準値 (ROWS=300, 最適化前)**: React initial 124.8ms/13857往復、re-render 53.9ms/7229、
    Turbo morph 405ms/51905。**上位往復の知見**: (1) React の __reactFiber$/__reactProps$
    expando write が全て越境 (~2700)、(2) morph は Attr#name 3003 + NamedNodeMap#length 1505 +
    Attr#value 1201 の属性イテレーションと、CustomEvent construct 1514 + dispatchEvent 1500 +
    defaultPrevented 1207 のイベントストームが支配的。
  - この実データで B4 の初弾 (expando JS 側化 / Attr const / factory 非変異化) を実装 (下記)。る

## 推奨順序

```
conformance:  A0 → A1 → B1 → C1 → B4(=D2) → (B2 ⇄ B3 定常化) → C2 → C3
高速化:       D4a (計測固定) → D1a → D1b → D1c → D2a-c (B4 と同時) → D3a → 残り
A2 の尻尾・D1d/D1e は合間に消化
```

各マイルストーンの完了時に `rake wpt:conformance` とベンチを再計測し、このファイルと
`docs/wpt-conformance.md` のスナップショットを更新する。
