# Dommy vs happy-dom vs jsdom — WPT 比較

Dommy(+ Dommy::Js::Quickjs)の立ち位置を、主要な Ruby 外の対抗馬 **happy-dom**(主ターゲット)
と **jsdom**(参照)に対して WPT で定量化する。初回測定 2026-07-05、再測定 2026-07-07(下記)。

## 2026-07-07 再測定 — 広さ(カバレッジ)比較: jsdom の to-run.yaml 分析

jsdom は WPT を CI で常時実行しており、`test/web-platform-tests/to-run.yaml` が
「実行する 103 ディレクトリ + 既知の期待失敗」を宣言している。これと Dommy の vendored
corpus(384 ファイル)を突き合わせた **カバレッジマトリクス**:

| 区分 | dirs | 内容 |
|---|---|---|
| **両方カバー** | 50 | dom コア (nodes/events/collections/traversal/ranges/abort/lists)、forms 全域 (18 dirs)、tabular-data、details/summary、template/script/noscript、grouping/text-level、title/base/link/style、url、webstorage、xhr、encoding、domparsing、FileAPI、css (color/cssom/selectors)、history/location |
| **jsdom のみ (=Dommy の未開拓)** | 53 | 下記「ギャップ分析」 |
| **Dommy のみ (=差別化)** | 5+ | **accname / wai-aria**(アクセシビリティ計算)、**dom/observable**(WICG Observable)、css-variables、css-syntax、**fetch/api 広域**(jsdom は fetch/api/headers のみ+cors) |

happy-dom は WPT を体系的に実行しておらず、公開された conformance レポートは存在しない
(→ 深さ比較は下の再実行テーブルで、我々の corpus 上で測る)。

### ギャップ分析 — jsdom が実行し Dommy が未 vendor の 53 dirs

jsdom 側の期待失敗数(to-run.yaml のエントリ数 = ファイルレベルの既知 fail)を添える。
**jsdom の fail が多い dir = 追いつくだけで勝てる差別化チャンス**、少ない dir = table stakes:

| 優先 | dir | jsdom 期待失敗 | 判断 |
|---|---|---|---|
| ★1 | custom-elements | 64 files + 24 subtests | Dommy は実装済み。jsdom は弱い → **差別化チャンス** |
| ★1 | shadow-dom | 43 files | 同上(Dommy 実装済み、要ブリッジ hardening) |
| ★2 | html/webappapis/* (10 dirs) | 各 0〜12 | jsdom ほぼ green = **table stakes**。atob/timers/microtask/events は Dommy 実装済みで安価 |
| ★2 | selection | 28 files | エディタ系フレームワークの前提。jsdom は概ね実装 |
| ★2 | html/semantics/selectors (:enabled/:checked 等) | 4 files + 46 subtests | Dommy のセレクタは強い → 高得点見込み |
| ★2 | html/semantics/disabled-elements | 0 | jsdom 全green の table stakes、安価 |
| ★3 | domxpath | 15 files | Dommy は backend XPath あり → 安価に差別化 |
| ★3 | uievents | 4 files | 小さい。イベント基盤は強い |
| ★3 | html/syntax (parser tests) | 21 files | Makiri パーサの検証になる |
| ★3 | html/infrastructure/*, html/obsolete | 3〜9 | 小粒 |
| ★4 | html/browsers/* (navigation/window 系 8 dirs) | **各 27〜60 (jsdom も弱い)** | ナビゲーションは範囲外だが、the-window-object 等の自己完結分は拾える |
| ★4 | css/* (cascade/display/scoping/cssom-view 等 8 dirs) | 各 12〜106 (jsdom 弱い) | Dommy は cascade 実装済み → css-cascade は差別化チャンス。cssom-view はレイアウト依存で範囲外多め |
| ★4 | html/semantics/embedded-content (img/media) | 53 files (jsdom も弱い) | 実ロードなしで通る DOM API 面のみ |
| ★5 | webmessaging | 74 files (jsdom 弱い) | MessageChannel は実装済み。cross-window 依存が多く選別要 |
| ★5 | websockets / WebCryptoAPI / canvas / pointer* / orientation / mediacapture | 12〜25 | 実装コスト大 or 範囲外。後回し |
| — | html/editing/dnd, interaction/focus | 4〜23 | UI 依存。focus の自己完結分のみ |

**結論(Phase 2 の優先順位)**: ①custom-elements + shadow-dom(差別化・実装済み)
→ ②webappapis + disabled-elements + semantics/selectors(安価な table stakes)
→ ③selection + domxpath + uievents + html/syntax → ④css-cascade + the-window-object の
自己完結分 → ⑤embedded-content の DOM API 面。

## 2026-07-07 再測定 — 深さ比較(384 ファイル corpus、ハーネス修正後)

unquoted `src=` を inline できないハーネスバグを修正して再実行(このバグで前回は一部
ファイルが NO-RESULTS になっていた)。実行: サブプロセス分離 + 12s timeout。

### 全体像

| 指標(384 ファイル中) | Dommy | jsdom | happy-dom |
|---|---|---|---|
| 完走 | **384** | 371 | 291 |
| fully-green | **319 (83%)** | 236 (61%) | 91 (24%) |
| ERR / HANG | **0 / 0** | 0 / 1 | 84 / 5 |

### per-directory subtest 合格率

| dir | Dommy | jsdom | happy-dom |
|---|---|---|---|
| dom | **99.5%** (33771/33932) | 94.5% (29521/31247) | 54.6% |
| html | **97.3%** (1636/1682) | 95.2% (1578/1657) | 56.8% |
| css | **98.7%** (3935/3985) | 3.4% ※1 | 63.4% |
| accname / wai-aria | **99.0% / 99.5%** | 0% / 0% | 0% / 0% |
| FileAPI | **98.5%** | 43.8% | 77.7% |
| fetch | **92.3%** | 0% ※2 | 0% ※2 |
| xhr | **90.5%** | 29.4% ※2 | 5.5% ※2 |
| encoding | **97.9%** | 0% ※3 | 18.8% |
| url | **99.9%** (1395/1397) | 97.3% (107/110) ※2 | 94.5% ※2 |
| domparsing | **98.0%** | 97.0% | 56.5% |
| webstorage | 97.7% | **100%** ※4 | 97.3% |

- ※1 css: この corpus は cascade/getComputedStyle 中心で、jsdom は計算スタイルを実装しない
  (実弱点だが corpus が Dommy 選定であることに注意)。
- ※2 fetch/xhr/url(データ供給): このハーネスは WPT サーバを持たないため、ネットワーク依存
  テストで jsdom/happy-dom が不利(jsdom 自身の CI は wptserve で xhr を広く通す)。
  **絶対値でなく「Dommy はサーバ emulation まで込みで通る」ことの証明**として読む。
- ※3 jsdom の encoding 0% はハーネスが TextEncoder を window に注入しないため(過小評価)。
- ※4 webstorage: jsdom は JS ネイティブなので lone surrogate を保持できる。Ruby 文字列の
  制約による Dommy の -28 は、**jsdom には存在しないギャップ**である点に注意(§実ギャップ)。

### Dommy の実ギャップ(jsdom green / Dommy not、2026-07-07 版 = 14 ファイル)

ハーネス非依存で信頼できる宿題リスト(≒ Phase 1 の具体的 backlog):

| ファイル | Dommy | 対処 |
|---|---|---|
| webstorage/storage_setitem.window.js | 1080/1106 | lone surrogate。**jsdom は通す** — QuickJS 側に文字列を保持する設計変更が要る(コスト大、判断保留) |
| webstorage/storage_builtins.window.js | 0/2 | Storage.prototype メソッドの identity(D2 と同根) |
| constraints/…patternMismatch.html | 74/85 | `v`-mode 正規表現。**QuickJS に pattern 評価を委譲すれば解ける**(Ruby Regexp でなく JS RegExp('v') を使う) — won't-fix から昇格候補 |
| constraints/…stepMismatch.html | 27/28 | 極小 float step の精度 1 件 |
| dom/nodes/Node-cloneNode.html | 131/135 | namespace prefix clone ×2 + implementation メソッド |
| dom/nodes/Element-closest.html | 27/29 | `:has(> :scope)` / state pseudo matcher |
| dom/nodes/Comment/Text-constructor | 15/16 ×2 | NUL 文字(Makiri fail-closed) |
| dom/nodes/attributes-namednodemap.html | 7/8 | setNamedItem/removeNamedItem 露出 |
| dom/traversal/NodeIterator / TreeWalker | 765/766, 760/761 | 各 off-by-one(assert_readonly 系) |
| dom/collections/HTMLCollection-as-prototype.html | 0/2 | named prop の prototype 継承経由アクセス |
| dom/abort/abort-signal-timeout.html | 0/1 | frame detach で timer 停止 |
| form-elements-filter.html | 1/2 | 個別 |

happy-dom green / Dommy not は 4 ファイルのみ(上記と重複 + textdecoder-arguments 3/4)。

### まとめ(2026-07-07)

- **fully-green 319 vs jsdom 236 vs happy-dom 91** — この corpus では Dommy が明確に先行。
  ただし corpus は Dommy 選定なので、公平な結論は「**両方がカバーする 50 dirs で Dommy は
  jsdom と同等以上、アクセシビリティ/fetch/css 計算で上回る**」まで。
- jsdom に負けている実項目は **14 ファイル・~40 subtests** に特定できた(上表)。
- 広さでは jsdom が 53 dirs 先行(前節)— Phase 2 の分母拡大で追う。

> ツール: `script/wpt-compare/`(Node、jsdom + happy-dom)。Dommy の数値は
> `rake wpt:conformance` の per-file 結果。

## 方法論と caveat(先に読むこと)

- **コーパス = Dommy が vendor した 245 ファイル**(`WptRunner.manifest`)。WPT 全体ではなく
  Dommy が選んだ部分集合なので、選択バイアスで Dommy にやや有利。
- 各ファイルを testharness で走らせ、`add_completion_callback` で pass/total を収集。
  happy-dom/jsdom はプロセス分離 + OS タイムアウト(ハング対策)。
- **「fully-green」= 全 subtest pass**(厳格)。668/669 のような惜しい pass は green に数えない。
- **ハーネス由来の caveat**(公平性のため明記):
  - **jsdom の encoding が全て 0** は、jsdom の window に `TextEncoder`/`TextDecoder` を
    このハーネスが注入していないため。jsdom の真の encoding 能力ではない(過小評価)。
  - iframe ナビゲーションと一部の外部リソース fetch はこのハーネスでは限定的。Dommy 本体は
    iframe を実装済みなので、iframe 依存テストで Dommy がやや有利に出る。
- なので **per-directory の絶対数は方向性の目安**。下記「確実な知見」がハーネス非依存で信頼できる。

## 全体像

| 指標(245 ファイル中) | Dommy | jsdom | happy-dom |
|---|---|---|---|
| 完走(結果を返した) | **245** | 207 | 165 |
| fully-green(全 subtest pass) | **192** | 122 | 55 |

Dommy がこのコーパスで明確に先行。happy-dom は完走 165 と低いが、その主因は下記の根本欠陥。

### per-directory の fully-green(files green / files)

| dir | Dommy | happy-dom | jsdom |
|---|---|---|---|
| accname | 3/6 | 0/6 | 0/6 |
| css | 8/12 | 1/12 | 1/12 |
| dom | 113/147 | 26/147 | 83/147 |
| domparsing | 11/12 | 4/12 | 10/12 |
| encoding | 8/11 | 6/11 | 0/11 ※caveat |
| html | 15/21 | 6/21 | 14/21 |
| url | 16/17 | 12/17 | 14/17 |
| wai-aria | 18/19 | 0/19 | 0/19 |

## 確実な知見(ハーネス非依存で検証済み)

### 1. happy-dom は classic script 間でトップレベル宣言を共有しない(ブラウザ非互換)

happy-dom は各 `<script>` を**隔離スコープ**で実行し、トップレベルの `class` / `const` /
**さらに `var`** すら次のスクリプトからグローバルに見えない。最小検証:

```
script1: class Foo{}  const BAR=42;  var BAZ=7;
script2: typeof Foo, typeof BAR, typeof BAZ
  jsdom     → function, number, number   (正しい: ブラウザと同じ)
  happy-dom → undefined, undefined, undefined
```

これは WPT の「support スクリプトで定義したヘルパーを本体が使う」パターン全般を壊し
(happy-dom の 71 ERR = `AriaUtils is not defined` 等)、**複数の inline script が状態を共有する
実ページ**も壊す。Dommy と jsdom は共有スコープで正しく動く。happy-dom の最大の弱点。

### 2. アクセシビリティは Dommy の明確な差別化

`wai-aria` 18/19、`accname` 3/6 に対し、**happy-dom も jsdom も両方 0**。computed role /
computed label(`test_driver.get_computed_role/label`)を Dommy は実装しており、両対抗馬には無い。

## Dommy の実ギャップ(jsdom が green で Dommy が not — 対応候補)

ハーネス由来でない、信頼できる Dommy の宿題(jsdom はクリアに pass)。dom/nodes 中心。
**2026-07-05 に一部着手**(✅=解消、△=部分、原因を併記):

| ファイル | 着手前 | 現在 | メモ |
|---|---|---|---|
| dom/nodes/Node-isSameNode.html | 8/9 | ✅ **9/9** | Document に `isSameNode` 未公開(js_methods+__js_call__ に追加)|
| dom/nodes/Node-appendChild.html | 8/11 | ✅ **11/11** | `window.frames` 実装(iframe 基盤)|
| css/cssom/getComputedStyle-detached-subtree.html | 1/1 | ✅ **6/6** | getComputedStyle が非レンダ(display:none iframe / flat tree 外)に空を返すよう修正 |
| dom/abort/reason-constructor.html | 0/1 | ✅ **1/1** | blank iframe の contentWindow 基盤 |
| dom/nodes/Comment-constructor.html | 12/16 | △ 13/16 | 2引数 WebIDL ToString(+1)。残 2=NUL(Makiri fail-closed)、1=cross-globals(nested-window Comment ctor 露出)|
| dom/nodes/Text-constructor.html | 12/16 | △ 13/16 | 同上 |
| dom/abort/abort-signal-timeout.html | 0/1 | 0/1 | frame detach で timer/timeout を止める semantics 未実装 |
| dom/nodes/Node-cloneNode.html | 120/135 | △ **131/135** | 欠けていた要素インターフェース 9 種を追加(HTMLTableColElement/HTMLDataListElement/HTMLFieldSetElement[既存 typo HTMLFieldsetElement を spec 名にリネーム]/HTMLFontElement/HTMLFrameElement 等 + tag マップ + BASE_CHAINS)、ProcessingInstruction インターフェースを seed。残 4=namespace prefix の clone 保持 ×2、createDocumentType/createDocument の implementation メソッド |
| dom/nodes/Element-closest.html | 27/29 | 27/29 | `:has(> :scope)` / `:invalid`(state pseudo)matcher ギャップ |
| dom/nodes/attributes-namednodemap.html | 7/8 | 7/8 | setNamedItem/removeNamedItem 露出 |
| html/…/the-input-element/radio.html | 10/12 | 10/12 | 未着手 |

**iframe/frames 基盤を実装**(2026-07-05): (1) getComputedStyle が非レンダ要素(display:none
iframe 内 / flat tree 外の unslotted shadow 光 DOM 子)に空 declaration を返す(`cascade.rb`
`not_rendered?` + Window `frame_element` 逆リンク)、(2) blank/srcdoc/about:blank iframe の
contentWindow を wire(WptRunner)、(3) `window[i]` / `window.frames[i]` = i 番目 iframe の
contentWindow(`frame_windows` + `globalThis.frames` alias)。**session 計 +12 subtests、
fully-green +3**、全スイート回帰ゼロ。残り: Comment/Text NUL(Makiri 制約)、cross-globals
(nested-window の Comment/Text は host-backed Constructor proxy で typeof≠function → 露出漏れ)、
abort-signal-timeout(frame detach timer)、Stimulus ApplicationStart(**cross-frame postMessage +
Stimulus fixture の vendor が別途必要** = 大きめの別作業)。

## まとめ

- **Dommy は happy-dom を広く上回る**(fully-green 192 vs 55)。happy-dom の cross-script scope
  欠陥は根本的で、実ページ互換にも響く。
- **アクセシビリティ(ARIA computed role/label)は Dommy 独自**。両対抗馬とも 0。
- Dommy が次に潰すべきは、上表の dom/nodes + abort の小ギャップ(実在の競合が pass する = 確実に取れる)。
