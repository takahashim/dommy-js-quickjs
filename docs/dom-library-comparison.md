# Dommy vs happy-dom vs jsdom — WPT 比較

Dommy(+ Dommy::Js::Quickjs)の立ち位置を、主要な Ruby 外の対抗馬 **happy-dom**(主ターゲット)
と **jsdom**(参照)に対して WPT で定量化する。測定日 2026-07-05。

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
