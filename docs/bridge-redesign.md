# ブリッジ再設計案 — 実フレームワーク（Turbo 等）の軽量テストに向けて

ステータス: ドラフト / 検討用
対象読者: dommy / dommy-js-quickjs / dommy-rack / capybara-dommy のメンテナ
最終更新: 2026-05-30

---

## 1. 目的とスコープ

### 1.1 動機

ヘッドレスブラウザ（Selenium / Cuprite / Playwright）は Turbo の「消費側」テスト
（レスポンスを受け取ってライブにページを書き換える挙動）には確実だが、**重い**:
ブラウザプロセス・実ネットワーク・レイアウト/レンダリング・V8 を伴う。

そこで **dommy（Ruby 製 DOM）+ quickjs（軽量 JS VM）+ dommy-rack（in-process Rack 接続）**
を土台に、**ブラウザを立てずに in-process で実フロントエンド JS（当面の標的は Turbo）を走らせて
テストする**、という構想がある。本書はそれを成立させるために必要な **JS⇄Ruby ブリッジの再設計**
を文書化する。

### 1.2 軽量 in-process がブラウザに勝てる点

「ブラウザの劣化版」ではなく、別カテゴリの利点を持つ:

- **fetch が in-process**: dommy-rack は Rack アプリを同一プロセスで呼ぶ。Turbo の `fetch` を
  ネットワークも別サーバも無しでアプリへ直結できる。
- **決定論スケジューラ**: 実時計が無い = タイミングレースが消える。非同期処理は
  「アイドルになるまでポンプ」で駆動する。
- **軽い起動**: quickjs の VM 起動はブラウザ/V8 比で桁違いに軽い。

この固有価値があるため、ブリッジ作り込みはオーバー投資ではなく合理的な正攻法と位置づける。

### 1.3 非ゴール

- 実ブラウザの完全な代替（レイアウト/可視性/描画依存の挙動の忠実再現）。
- 任意のフロントエンドフレームワークの汎用サポート。**標的は Turbo（と前提となる Stimulus）に限定**し、
  有限の標的として駆動する。
- happy-dom 本家テストスイートの実行（JS 実装を直接 import する単体テストで、Ruby 実装には適用不能）。

---

## 2. 現状アーキテクチャと限界

### 2.1 現状

- Ruby DOM ノードは JS 側に **無名 ES Proxy（`new Proxy({}, ...)`）** として渡る
  （`lib/dommy/js/host_bridge.rb` の `HOST_RUNTIME_JS` 内 `makeProxy`）。
- プロパティ/メソッドアクセスは ABI へルーティング:
  `__js_get__(name)` / `__js_set__(name, value)` / `__js_call__(method, args)`。
- メソッドか否かは各クラスの `__js_method_names__`（メソッド名のみ）で判定。
- `querySelectorAll` は **素の JS 配列**として返る（ライブ NodeList ではない）。
- backend は quickjs.rb の VM（`eval` / `define_function` / `call` / `drain_jobs!` / `gc!`）。

### 2.2 限界（実フレームワークを通せない理由）

ブリッジは「Ruby を真実の源にして、JS には薄い Proxy を見せる RPC」なので、**DOM の JS 型システム**
が存在しない:

| 実アプリ JS がやること | 素 Proxy だと |
|---|---|
| `node instanceof Element` / `event.target instanceof HTMLElement` | ✗ 型情報なし |
| `class X extends HTMLElement { connectedCallback(){} }` + `customElements.define` | ✗ `HTMLElement` が実コンストラクタでない |
| `new CustomEvent("x", {detail})` を JS 側で生成・dispatch | ✗ JS 型として存在しない |
| `Object.prototype.toString.call(el)` → `[object HTMLDivElement]` | ✗ `Symbol.toStringTag` 無し |
| `Array.prototype.slice.call(nodeList)` / prototype メソッド借用 | ✗ |
| ライブ `HTMLCollection`（`el.children` 等）の整合 | ✗ スナップショット配列 |
| `e instanceof DOMException` | ✗ JS 例外型として無い |

さらに **testharness.js（WPT）自体がこの型システムを前提**にする
（`assert_class_string` は `Object.prototype.toString.call`、`assert_throws_dom` は `instanceof DOMException`）。

加えて **コスト/セマンティクス軸**: プロパティアクセス毎に Ruby⇄JS ラウンドトリップ＋marshalling が走り、
getter 副作用・同一性・ライブコレクション整合の再現が ABI 越しに重い。

### 2.3 規模の実測（dommy 本体）

- DOM インターフェース相当クラス: **168**（うち HTML 要素 **58**、Event 系 **18**）。
- `__js_method_names__`: 約 28 箇所 / 7 ファイル。**メソッド名のみ**で、継承チェーン・プロパティ一覧・
  IDL 型は JS に未公開。
- 必要なサブシステム（fetch / MutationObserver / history / location / DOMParser / template / custom_elements）
  は **dommy に既に実装済み**。よって本再設計の費用は「DOM 機能の再実装」ではなく
  「**型付きブリッジ層＋逆方向生成＋各サブシステムの“JS から本物の型で見える”配線**」に集中する。

---

## 3. 設計の二軸

再設計は独立だが補完的な 2 軸からなる。

### 軸 1: 型システム層

JS 側に本物のプロトタイプ階層・コンストラクタ・型タグを構築し、各ノードをその型のインスタンスとして見せる。

#### 1a. インターフェースメタデータの公開（dommy 側）

各インターフェースについて以下を返す ABI を追加（例: `__js_interface_info__`）:

- インターフェース名（例 `"HTMLDivElement"`）
- 親インターフェース（継承チェーン: `HTMLDivElement → HTMLElement → Element → Node → EventTarget`）
- メソッド名一覧 / **プロパティ名一覧** / （可能なら readonly/writable）

継承は Ruby の `ancestors` から概ね導出可。**プロパティ列挙が現状ゼロ**（`__js_get__` が何でも受ける
開放設計）なのが主コスト。既知プロパティはプロトタイプ getter 化し、未知は Proxy フォールバックで補う方針。

> 規模: M〜L / 1〜2 週。168 クラスに触れるが自動導出＋フォールバックで圧縮可能。

#### 1b. JS 側プロトタイプ階層＋コンストラクタ構築

メタデータから一度だけブートストラップ:

- `EventTarget.prototype → Node.prototype → … → HTMLElement.prototype → HTMLDivElement.prototype` を
  ABI 委譲の getter/メソッドで生成。
- 各 prototype に `Symbol.toStringTag` を付与。
- コンストラクタ関数（`window.HTMLElement` 等）を生成し `.prototype` を相互リンク。
- `makeProxy(handle)` がハンドル→インターフェース名を引いて正しい prototype を装着。

これで `instanceof` が自動成立。重要な ~30〜40 型に絞れる（168 全部は不要）。

> 規模: M / 1〜1.5 週。メタデータが揃えば機械的。

#### 1c. JS からの `new`（Event / CustomEvent / DOMException 等）

`new CustomEvent(...)` を **JS→Ruby `.new`→proxy** で実体化する逆方向生成。現ブリッジに無い経路。
小ヘルパ（例 `__rbHost.construct(interfaceName, args)`）＋ Ruby 側ファクトリで対応。値型中心なら素直。

> 規模: M / 1 週。

#### 1d. `class X extends HTMLElement` + JS 定義カスタム要素 ⚠️ 最難所

Turbo の `turbo-frame` / `turbo-stream` の前提。要求:

- `HTMLElement`（および要素サブクラス）が **JS から `super()` 可能な実コンストラクタ**で、
  構築結果が Ruby ノードに裏打ちされる。
- `customElements.define(name, JSClass)` に **JS クラス**を登録でき、dommy のパーサ /
  `createElement` / upgrade ライフサイクルが **JS 側コンストラクタと `connectedCallback` /
  `disconnectedCallback` / `attributeChangedCallback` を呼ぶ**よう双方向化。
- 仕様の「HTMLElement コンストラクタが upgrade 対象の既存要素を返す」トリックの実装
  （ネイティブエンジンでも難所）。
- DOM 移動時の connected/disconnected の発火タイミング、`observedAttributes` の配線。

現状 dommy のカスタム要素は **Ruby クラス**（`define(name, klass)`）。JS 定義クラスが dommy の
upgrade ライフサイクルに参加できるよう、Ruby 側（`custom_elements` / `node_wrapper_cache`）が
**JS へコールバック**する必要がある。

> 規模: L / 高リスク / 2〜4 週（分散大）。**本再設計の不確実性の支配項**。

#### 1d 実装パス（確実化のための段階設計）

1d の難所は「新規発明」ではなく、**custom-elements polyfill / jsdom が実装済みの “construction stack”
パターン**に縮約できる。dommy は DOM 側機構（registry / upgrade / reaction / observedAttributes /
lifecycle）を **Ruby クラス向けに実装済み・WPT 固定済み**なので、1d は「実証済みパターンの移植＋配線」
として確実化できる。鍵は **不確実性（分散）を Step 0 で隔離して畳む**こと。

##### 核心: construction stack を純 JS で組む（quickjs で成立する）

仕様の「コンストラクタが upgrade 対象の既存要素を返す」挙動は、**ベースクラスがオブジェクトを return
すると派生の `this` になる**という ES2015 規則で実現できる。quickjs は `class` / `super` / `new.target` /
`Reflect.construct` / `setPrototypeOf` を持つため、そのまま動く:

```js
const constructionStack = [];          // upgrade 中の既存要素を積む

function HTMLElement() {
  let el;
  if (constructionStack.length > 0) {
    el = constructionStack[constructionStack.length - 1];   // upgrade: 既存ノードを採用
    if (el === PENDING) throw new TypeError("Illegal constructor");
  } else {
    const handle = __rb_create_element_for(new.target);     // new MyEl(): Ruby が新ノード生成
    el = makeProxy(handle);
  }
  Object.setPrototypeOf(el, new.target.prototype);          // instanceof MyEl を成立させる
  return el;                                                 // ← 派生の super() で this になる
}

// Ruby から呼ぶ upgrade ヘルパ
__rbHost.upgrade = (handle, name) => {
  const Ctor = registry.get(name);
  const el = makeProxy(handle);
  constructionStack.push(el);
  try { Reflect.construct(Ctor, [], Ctor); }   // MyEl 本体実行・super() が el を採用
  finally { constructionStack.pop(); }
  return el;
};
```

この十数行が quickjs で期待通り動くか **だけ**が、1d の本質的不確実性のほぼ全て。

##### 1a/1b との合流で expando 問題が消える

ユーザのクラスは `this.count = 0` のような **DOM 外プロパティ（expando）** を書く。現状の
「`{}` への catch-all Proxy」はこれを `__js_set__` に流してしまい相性が悪い。これを避ける鍵:

> **1a/1b を「catch-all Proxy」ではなく「実オブジェクト＋ prototype に DOM アクセサ（ABI 委譲
> getter/setter）」モデルで作る。**

すると expando は普通の own プロパティ、DOM アクセスは prototype 経由、`instanceof` も自然成立し、
`class extends HTMLElement` + `this.x=` がそのまま通る。**1d は 1a/1b の上にほぼ落ちてくる**。
catch-all を残したい場合は `new Proxy(realTargetWithProto, handler)` のハイブリッドも可。

##### dommy 側は「再ポイント」だけ

dommy の既存機構に足すのは 2 点のみ:

- カスタム要素定義を **「Ruby クラス or JS 定義ハンドル」** の多態にする 1 つの seam。
- upgrade / lifecycle が JS 定義なら `__rbHost.upgrade(handle, name)` /
  `__rbHost.invokeLifecycle(handle, "connectedCallback", args)` を呼ぶ配線。

仕様が複雑な部分（いつ upgrade するか・reaction タイミング・observedAttributes フィルタ）は
**既済・WPT 固定済み**。これが「確実に」できる最大の根拠。

##### 段階パス（各段が独立に検証可・フォールバック付き）

| Step | 内容 | 検証 | 退避 |
|---|---|---|---|
| **0. 純 JS スパイク**（数時間〜1日） | 上の construction stack を **dommy 抜き**で実装。`new Derived()` と `Reflect.construct`(upgrade)、`instanceof` / prototype / コンストラクタ本体実行 / expando / Illegal guard を assert | quickjs 単体 | quirk があればここで最安で発見 |
| **1. 同期 createElement upgrade** | `createElement("my-el")`→ Ruby 生成 →`upgrade`→ 型付き proxy。**parser 非関与** | Ruby から「dommy ノード」かつ JS から「instanceof MyEl」 | — |
| **2. ライフサイクル** | connected / disconnected / attributeChanged / adopted を JS メソッドへ配線 | 各コールバック個別 | reaction を同期実行（microtask batch は後回し）= F3 |
| **3. parser 駆動 upgrade** | `<my-el>` のパース → 定義到着時 upgrade（`upgrade_existing`）。順序 / reaction queue の機微 | 既存 WPT カスタム要素シナリオを JS 定義で | **define-before-parse 限定** = F1 |
| **4. 実物** | 最小 Lit 風要素 → `turbo-frame` 本体 | Turbo シナリオ | — |

**Step 0 が最重要**: 境界（Ruby⇄JS）を入れる前に、新規カーネルを隔離して潰す。ここが通れば
残りは「読める配線」に収束し、不確実性（分散）が一気に畳まれる。

##### フォールバック（“確実”＝段階的縮退で全否定を避ける）

- **F1: define-before-use 限定**。要素出現前に `customElements.define` 済みを要求し、最難の遡及
  upgrade を外す。**Turbo は import 時に要素定義 → 以後に Turbo HTML 処理**なので適合。
  テストでも define 順は制御可能。
- **F2: 任意 JS からの `new MyEl()` を当面外し**、createElement / parser 経路のみ。面を縮小。
- **F3: reaction を同期実行**（spec の microtask バッチ化は順序依存テストが要るまで保留）。

これらで動く部分集合を早期に出し、後から厳密化できる＝実務的な「確実性」。

##### 既存の青写真（実証済み）

- **jsdom のカスタム要素実装**: まさに construction stack ＋ `Reflect.construct`。裏付けノードが
  JS か Ruby かの違いだけで、機構は直輸入可能。
- **@webcomponents/custom-elements polyfill**: 旧ブラウザ向けに同ダンスを純 JS で実装。

「ネイティブ実装が難所」と言いつつ **polyfill / jsdom が純 JS で解決済み**＝ quickjs 上でも再現できる、
というのが確実化の根拠。

##### 残存リスク（Step 0 で大半 retire）

1. quickjs の `Reflect.construct(C, args, newTarget)` と「ベースが return したオブジェクトが `this` に
   なる」挙動の細部 → **Step 0 で確認**。
2. 同一 Ruby ノード → 同一 JS インスタンスの安定対応（handle キャッシュで概ね担保、upgrade 時に
   紐付け固定）。
3. `super()` 前の field initializer 順、constructor 内 DOM 変更の reaction 再入（spec 上禁止、ガード可）。

### 軸 2: セマンティクス / コスト層

#### 2a. ライブコレクション

`el.children` / `getElementsByClassName` 等のライブ `HTMLCollection`（整数インデックストラップ＋
`length`＋iterator＋`namedItem`）を Ruby 側ライブ集合へ委譲。`querySelectorAll` のスナップショット
（=`NodeList`）も型として整える。

> 規模: M / 1〜1.5 週。

#### 2b. サブオブジェクト同一性

`el.style === el.style`、`classList`、`dataset` が毎回新 proxy だと同一性が壊れる。
ノード proxy ごとにサブオブジェクトをメモ化。

> 規模: M / 0.5〜1 週。

#### 2c. メソッド / `this` 同一性

メソッド参照のキャッシュ（フレームワークが稀に依存）。

> 規模: S〜M / 0.5 週。

#### 2d. 性能

プロパティアクセス毎の Ruby⇄JS ラウンドトリップ＋marshalling。テスト用途なら許容圏。
バッチ/高速パス/メタデータキャッシュは需要次第。**初期は後回し**。

> 規模: 可変。

#### 2e. WebIDL 強制 / 例外セマンティクス

null/undefined・数値強制・DOMString 変換・例外を DOMException で送出。長い裾野、漸進的に。

> 規模: M（漸進）。

---

## 4. 信頼性: WPT-JS による固定と診断力

### 4.1 問題: テストの診断力が落ちる

軽量ドライバ上で Turbo を走らせると、テストが赤になったとき原因が
**「アプリのバグ」か「ブリッジの穴/タイミング差」か**切り分けられなくなる恐れがある。
テストの価値は「失敗が原因を一意に指す度合い（fault localization）」にほぼ比例するため、これは致命的。

### 4.2 解: 層ごとに独立した適合性で固定する

- **Ruby DOM 層** ← WPT（dommy 本体で既に推進中。Ruby に手移植された WPT シナリオ群）。
- **JS ブリッジ層** ← **WPT-JS（testharness.js を実行する WPT の JS テスト）でブリッジ自体を固定**。

WPT-JS は「適合性のおまけ」ではなく、**軽量ドライバをブラウザ代替として信頼できるものに変える中核**。
ブリッジが適合性で固定されて初めて、Turbo テストの赤が「アプリのバグ」を指すようになる。
固定が無ければ「軽いが当てにならない」になり、本来の目的を損なう。

> 軸 1（型システム）への投資は、WPT-JS の型システム検証（`instanceof` / prototype / `[object X]` /
> `DOMException`）を通す作業とほぼ資産共有になる。

### 4.3 被験体（subject under test）をティアで明示する

- **サーバ契約テスト（JS なし）**: 「このリクエストにこの `<turbo-stream>` / HTML を返す」。
  capybara-dommy / dommy-rack で一意・診断的に書ける。**Turbo アプリで検証したいことの大半はここ**。
- **Turbo 消費テスト（JS あり・少数）**: 「frame リンクのクリックで該当 frame が差し替わる」等。
  「JS/Turbo 統合層を触っている」と明示的にラベル付けし、ブリッジの注釈付きで受け入れる。
- 「ブラウザっぽい無差別スイート」（何が落ちたか言えないテスト群）は作らない。

---

## 5. 段階的実装計画

### Stage 0: 1d PoC（ゲート）

`turbo-frame` 相当の最小カスタム要素が、JS の `class extends HTMLElement` で
**定義 → upgrade → `connectedCallback` 発火**まで通るかを最初に検証する。
具体的な段階設計（**Step 0 純 JS スパイク → Step 4 実物**）とフォールバック（F1〜F3）は
§3「1d 実装パス（確実化のための段階設計）」を参照。**まず Step 0（dommy 抜きの純 JS スパイク）から**着手する。

- 通れば: 残りは「有限の配線作業」として見通せる。
- 詰まれば: コストが跳ねるので、Ruby 側 Turbo シム（§7.1）への切替を早期判断。

### Stage 1: dommy-rack + quickjs（土台）

- セッション中、持続する `window` / JS コンテキストを保持。
- Turbo の `fetch` → dommy-rack 経由で Rack アプリ **in-process**。
- `history.pushState` / `location` / DOMParser / template / MutationObserver を
  **JS から本物の型で**配線。
- スケジューラのポンプ（drain microtasks → advance → idle まで）。
- 軸 1 の 1a–1c ＋ **1d**、軸 2 の 2a / 2b。

### Stage 2: capybara-dommy + quickjs（ドライバ統合）

- ドライバに **「JS モード」** を追加: クリック / submit を Ruby で遷移合成せず、
  **JS イベントとして発火**して Turbo に横取りさせる（rack-test のナビゲーション中核を JS モードで無効化）。
- **Capybara の暗黙待ち（`has_content?` 等の自動リトライ）↔「スケジューラをポンプして再クエリ」** に写像。
  決定論なのでフレークしない。

> rack-test 系は本来「ナビゲーション=HTTP ラウンドトリップ / ページ作り直し / JS 状態破棄」。
> Turbo は逆に「クリックを JS が横取り→ fetch →同じ持続コンテキストでライブ DOM 差し替え」。
> Stage 2 はこのモデル衝突を「JS モード」で吸収する。

---

## 6. 非同期 / スケジューラモデル

- dommy のスケジューラは決定論（`advance_time` でのみ進む）。
- Turbo は `await nextRepaint()` / rAF / microtask / fetch promise / MutationObserver タイミングに依存。
- ハーネスは **「microtask drain → scheduler advance → 再度 drain」を quiescent になるまで反復**して駆動する。
- これは「Turbo が勝手に動く」のではなく **ハーネスが時計を駆動する**前提。テスト用途では制御可能で、
  むしろ Capybara の待ちセマンティクスと自然に一致する（§5 Stage 2）。
- 制約: Selenium 風の `done()` コールバック型・実時間待ちはサポート外（README の既存制約と同様）。

---

## 7. 検討した代替案

### 7.1 Ruby 側 Turbo シム（実行ではなく挙動の再現）

@hotwired/turbo を実走させず、Drive / Stream の観測可能挙動を dommy-rack に Ruby で実装する。

- 長所: **1d も JS 型システムも不要**。数日〜数週。dommy の「消費者は Ruby」哲学と一致。
- 短所: **エミュレーション**であり実 Turbo とドリフトしうる。緑≠本番 OK、赤も「アプリ or シム未実装」
  が切り分け困難。「Turbo 自体の正しさ」は検証できない。
- 使いどころ: 目的が「**Turbo アプリの挙動をテストしたい**（Turbo 自体は信頼）」なら、コスパ・哲学整合で優位。

### 7.2 DOM を JS で実装（jsdom / happy-dom 方式）

- DOM が最初から JS オブジェクトなので `instanceof` / prototype / `class extends` がタダ、ブリッジコストゼロ。
- だが dommy の「pure Ruby DOM」「消費者は Ruby」という価値を捨てる別製品になる。168 クラスの資産も無駄に。
- 「消費者が Ruby」の用途（Ruby テストが本物の DOM を直接触る）は JS 実装では埋められない。**却下**。

### 7.3 実ヘッドレスブラウザ

- Turbo 消費テストには確実だが、本構想の出発点である「**重さ**」がそのまま欠点。回避対象。

### 判断軸

| 目的 | 推奨 |
|---|---|
| アプリが正しい Turbo レスポンスを**返す**ことの検証 | dommy-rack / capybara-dommy（**JS なし**） |
| Turbo アプリの挙動テスト（Turbo 自体は信頼） | Ruby 側 Turbo シム（§7.1） |
| **実 Turbo が消費して DOM を書き換えること**の軽量検証 | 本再設計（軸 1＋1d＋配線、WPT-JS で固定） |
| フロントエンド全体の忠実検証 | 実ヘッドレスブラウザ |

---

## 8. 忠実度の天井とスコープ

軽量路線は **実ブラウザ挙動のサブセット**を追う。受け入れるギャップ:

- **得意**: frame 遅延ロード、turbo-stream 適用、form submit→stream、Stimulus、Drive の body 差し替え。
- **苦手 / 永続的に脆い**: 実レイアウト / 可視性依存の挙動（dommy は HTML レベル可視性のみ）、
  DOM の稀な隅、Turbo のバージョン追従（標的が動く＝適合スイートで追い続ける運用が要る）。

このギャップを **WPT-JS ＋ Turbo シナリオの適合スイートで明示的に管理**できる限り実用になる。
管理しないとギャップが暗黙にテストの意味を侵食する。

---

## 9. 見積りまとめ

前提: DOM 仕様と両リポジトリに精通した開発者 1 名の集中作業。不確実性は大きめ。

| 範囲 | 内容 | 目安 |
|---|---|---|
| 型検証 + 命令的アプリ JS（1d なし） | 軸1 の 1a–1c ＋ 軸2 の 2a/2b | **5〜7 週** |
| **Turbo 実走**（1d 込み） | 上記 ＋ 1d ＋ fetch/history/MO/template 配線 ＋ Stage2 | **おおむね 2〜2.5 ヶ月**（1d が支配項） |

WPT-JS ハーネス整備は型検証作業と資産共有のため、上記に内包できる部分が大きい。

---

## 10. リスクと未解決点

1. **1d（JS 定義カスタム要素）の正しさ** — 最大の不確実要因。Stage 0 PoC で先に潰す。
2. **MutationObserver の型とタイミング** — Turbo の frame/stream 検知が依存。
3. **async/rAF の順序** — ポンプ設計に依存。Capybara 待ちとの写像で吸収する想定。
4. **fetch のブリッジ忠実度** — Response の `.text()` / headers が JS から正しく使えること（ストリーミングは不要）。
5. **dommy 本体への横断改修** — メタデータ公開・逆方向生成・JS 定義カスタム要素は dommy 側が
   「JS エンジンに駆動されうる」前提のフックを持つ必要があり、**dommy ↔ dommy-js-quickjs の横断作業**になる。
6. **quickjs.rb の能力** — prototype/コンストラクタは `eval` で純 JS 構築でき、ネイティブクラス対応は不要。
   Ruby から `new` を起動する小ヘルパ（`__rbHost.construct`）の追加で足りる見込み（要確認）。
7. **Turbo バージョン追従の運用コスト** — 標的が動く前提で適合スイートを維持する体制が要る。

---

## 11. 次アクション

1. 本書をレビューし、目的（実 Turbo 実走 / Turbo 挙動テスト）の優先度を確定する。
2. **§3「1d 実装パス」の Step 0（純 JS スパイク）** に着手し、construction stack が quickjs 上で
   期待通り動く（`instanceof` / prototype / コンストラクタ本体実行 / expando / Illegal guard）ことを
   dommy 抜きで検証する。← 最大の不確実性をここで畳む。
3. Step 0 が通れば Step 1（同期 createElement upgrade）へ。並行して **WPT-JS 最小ハーネス**
   （testharness.js ロード＋グローバル配線＋結果回収）を立て、ブリッジ固定の足場を作る。
4. Step 0/1 の結果で本格実装 or §7.1 シムへの分岐を判断する。
