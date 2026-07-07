# 実装計画: ナビゲーション N0 + N1

NavigationDelegate ポート導入 + アンカー activation + fragment 同一文書ナビ

親設計: `docs/navigation-design.md`(承認済み、D1〜D7 確定)
関連: `docs/conformance-roadmap.md`(Phase 3/4)、`docs/dom-library-comparison.md`
ステータス: 実装待ち / スコープ確定(N0+N1、submit 集約は N2 へ遅延)

---

## Context

Dommy は「単一ドキュメント内の DOM+JS」では jsdom 同等以上(WPT 99.2%、fully-green 319 vs
jsdom 236)だが、**ページ遷移(ナビゲーション)を持たない**。これが Turbo unit 52.6% で
止まる直接原因であり、「ヘッドレスブラウザ」として不足する最大の要素。レイアウト完全再現は
捨て、ナビの「観測可能な核」だけを spec 準拠で実装する。

本 PR の範囲(ユーザー確定):

- **N0**(ポート導入)+ **N1**(アンカー activation + fragment 同一文書ナビ)。
  アンカーは現状 default action が皆無なので **純粋に加算的で低リスク**。
- フォーム submit の core 集約(設計 D4 の form 側)は既存の driver/session/capybara の
  3ジェムに跨るため **N2 へ遅延**(本 PR では既存 submit 経路を一切触らない)。

### 探索で確定した重要事実(3 Explore エージェント)

- **`Element#click`(`element.rb:2040`)に activation seam が既存**: `pre_click_activation_state`
  / `run_post_click_activation` / `restore_pre_click_activation`(base は no-op、
  `HTMLInputElement` の checkbox/radio のみ override)。ただし `return not_canceled if pre.nil?`
  で post をスキップするため、アンカー(pre 無し)はこの seam に載らない → `click` の再構成が要る。
- **driver/synthetic クリックは別経路**: `EventSynthesis.click`(`event_synthesis.rb:18`)は
  生 MouseEvent を dispatch し `default_prevented?` を返すだけで、`Element#click` を通らない。
  両経路で activation を発火させる集約が必要。
- **`Element#anchor_href`(`element.rb:2319`)は既に絶対 URL** を `window.location.href` 基準で解決。
- Location/History は `Window#fire_hashchange`/`fire_popstate`(`window.rb:270,277`)で同一文書
  イベントを既に発火。`Location#__internal_set_url__`(`location.rb:90`)は `#`-only を特別扱い。
- **フォーム直列化は core に既存**(N2 で再利用): `Dommy::Interaction::FormSubmission`
  (`interaction/form_submission.rb`)と `Dommy::FormData`(`form_data.rb`)。dommy-rack は
  その薄いサブクラス。
- **バグ2件を N1 で是正**: (a) hashchange が `CustomEvent`(真の `HashChangeEvent` でなく、
  detail が全 URL でなく bare hash)。(b) History pushState が `__internal_set_url__` 経由で
  fragment 変更時に **hashchange を余計に発火**(spec は pushState で hashchange 不発火)。
- **NavigationDelegate は未存在**。最も近い既存 host seam は `window.websocket_connector`
  (`window.rb:54`、attr_accessor)。これを踏襲する。
- `:target` 疑似は `Internal.target_id`(`css_pseudo_handlers.rb:210`)が `location.hash` を
  都度読むので、location の hash が更新されれば `:target` は自動追従(追加実装不要)。

---

## Phase N0 — ポート導入 + NullDelegate(挙動変更ゼロ)

### 新規: `dommy/lib/dommy/navigation.rb`

- `module Dommy::Navigation`
  - `NullDelegate`: `navigate(url:, method: "GET", body: nil, headers: {}, replace: false, source:)`
    と `traverse(delta)` を持ち、実行せず `attempts`(Array of Hash)に記録するだけ。
    `attr_reader :attempts`。テストで「navigate が呼ばれたこと」を assert できる。
  - 契約はダックタイピング(モジュールは契約のドキュメント兼既定実装)。

### `dommy/lib/dommy/window.rb`

- `attr_accessor :navigation_delegate`(`websocket_connector` の隣、`window.rb:54` を踏襲)。
  `initialize` で `@navigation_delegate = Navigation::NullDelegate.new`。
- **集約メソッド** `__internal_navigate__(url:, method: "GET", body: nil, headers: {},
  replace: false, source:)`: `@navigation_delegate&.navigate(...)` を呼ぶだけの唯一の発火口。
  以後の全 firing point はこれを通す。
- `require "dommy/navigation"` を `dommy.rb` の require 群に追加。

### 検証(N0)

- `cd dommy/gems/dommy && bundle exec rake test`(3339)green 維持のみ(観測変化なし)。
- quickjs 側 `bundle exec rake test`(596)green。

---

## Phase N1 — アンカー activation + fragment 同一文書ナビ + HashChangeEvent 是正

### 1. activation-behavior の集約(`dommy/lib/dommy/element.rb`)

- 新 hook `def activation_behavior(_event) = nil`(base no-op、`element.rb:2059` 付近の
  既存 hook 群に追加)。
- `Element#click`(`element.rb:2040`)を再構成し、pre 有無に関わらず post-dispatch で
  activation_behavior を走らせる:

  ```ruby
  def click
    pre = pre_click_activation_state
    event = MouseEvent.new("click", "bubbles" => true, "cancelable" => true, "button" => 0)
    not_canceled = dispatch_event(event)
    if not_canceled
      run_post_click_activation(pre) unless pre.nil?   # checkbox/radio 確定(既存)
      activation_target&.activation_behavior(event)     # アンカー等(新規)
    elsif pre
      restore_pre_click_activation(pre)
    end
    not_canceled
  end
  ```

- `activation_target`: 自身または最近接の activation behavior を持つ祖先(まず `<a href>`。
  `closest("a[href]")` で近似。submit ボタンは N2)。base は `self`。

### 2. 両経路の統一(`dommy/lib/dommy/interaction/event_synthesis.rb`)

- `EventSynthesis.click(element)` の末尾で、`click` イベントが非キャンセルなら
  `element` の `activation_target&.activation_behavior(click_event)` を実行してから
  `default_prevented?` を返すよう変更(synthetic/driver クリックでもアンカー default action が
  発火するように)。
- checkbox/radio は既に `field_interactor` 側で処理されるので、activation_target が `<a>` の
  ときだけ発火する設計にして二重発火を避ける。
- 注意: この変更で `Browser#click_link`(`browser.rb:164`、現状ナビ無し)と capybara の
  `click_link` が **delegate 経由でナビを試みる**ようになる。既定 NullDelegate は記録のみ
  なので観測上は安全(dommy-rack Session は delegate を設定せず Ruby メソッドで実ナビ
  するため二重ナビにならない)。

### 3. アンカーの follow-the-hyperlink(`dommy/lib/dommy/html_elements.rb` `HTMLAnchorElement`)

- `def activation_behavior(event)`:
  - `href` 属性が無ければ何もしない。
  - `target_url = anchor_href`(絶対 URL、既存)。
  - `download` 属性ありは範囲外 → 何もしない。
  - **same-document 判定**: `target_url` が現在の location と scheme/host/port/path/query が
    同一で **fragment だけ異なる**なら → `window.location.__internal_set_url__("#" + fragment)`
    で hash を更新(既存の hashchange 経路 + `:target` 自動追従)。
  - それ以外(cross-document)→ `window.__internal_navigate__(url: target_url, method: "GET",
    source: :link)`。
  - `HTMLAreaElement`(`html_elements.rb:4149`)も同様(コード共有 mixin か委譲)。

### 4. HashChangeEvent の spec 準拠化

- 新 `HashChangeEvent < Event`(`event.rb`、`PopStateEvent`(`event.rb:611`)を雛形に)。
  `oldURL`/`newURL`(full URL の DOMString)を公開する `__js_get__`。BASE_CHAINS には
  既に `%w[HashChangeEvent Event]`(`dom_interfaces.rb:81`)があるので instanceof は解決済み。
- `Window#fire_hashchange(old_url, new_url)`(`window.rb:277`)を full-URL 引数に変更し
  `HashChangeEvent.new("hashchange", "oldURL" => old_url, "newURL" => new_url)` を dispatch。
  呼び出し側 `Location#__internal_set_url__`(`location.rb:105`)と hash= setter
  (`location.rb:52`)を、bare hash でなく **変更前後の full href** を渡すよう修正。

### 5. pushState の hashchange 二重発火を抑止(`history.rb` / `location.rb`)

- `Location#__internal_set_url__` に `fire_hash:` キーワード(既定 true)を追加。History の
  `push`/`replace`(`history.rb:81,93`)は `fire_hash: false` で呼び、pushState/replaceState
  では hashchange を発火させない(spec: pushState は hashchange を起こさない)。popstate
  経路(`go`、`history.rb:123`)は現状通り popstate のみ。

### 6. Location の cross-document 経路を delegate へ配線(`location.rb`)

- `assign`/`replace`/`href=` が **fragment 変更のみでない**(= cross-document)場合、
  `@window.__internal_navigate__(url:, method: "GET", replace: (method=="replace"),
  source: :location)` を呼ぶ。fragment-only なら従来通り same-doc(hashchange)。
- `reload`(現状 no-op、`location.rb:77`)→ `@window.__internal_navigate__(url: href,
  method: "GET", replace: true, source: :reload)`。
- **後方互換**: パーツ更新は従来通り行い、delegate 通知を「追加」するだけ(NullDelegate
  既定なら観測変化は delegate 記録のみ)。

### 検証(N1)

- **新規 dommy テスト**(`test/test_navigation.rb` 想定):
  - フラグメントリンク click → `location.hash` 更新 + `hashchange`(HashChangeEvent、full URL)
    + `:target` が新 id にマッチ。
  - cross-doc アンカー click → NullDelegate.attempts に `{url:, source: :link}` 記録、
    location は不変。
  - `preventDefault()` した click → ナビ試行なし(attempts 空、hash 不変)。
  - `location.assign("/x")` / `reload()` → attempts に記録。fragment `location.hash="#y"` は
    delegate を呼ばず hashchange のみ。
  - pushState でフラグメント変更 → hashchange **不発火**、popstate も不発火(spec)。
- 既存スイート全 green: dommy `rake test`、quickjs `rake test`、
  および `EventSynthesis.click`/driver を使う `test_interaction.rb` 等に回帰なし。
- quickjs 側: WPT `html/browsers/browsing-the-web/scroll-to-fragid` の**非スクロール分**を
  vendor(fragment ナビ + `:target` の観測分)。スクロール依存/実 iframe 依存は drop し
  理由を記録。

---

## 影響ファイル一覧

**dommy(`gems/dommy`)**:

| ファイル | 変更 |
|---|---|
| `lib/dommy/navigation.rb` | 新規(NullDelegate) |
| `lib/dommy/window.rb` | `navigation_delegate` accessor、`__internal_navigate__`、`fire_hashchange` full-URL 化 |
| `lib/dommy/element.rb` | `click` 再構成、`activation_behavior`/`activation_target` hook |
| `lib/dommy/interaction/event_synthesis.rb` | synthetic click で activation を発火 |
| `lib/dommy/html_elements.rb` | `HTMLAnchorElement`/`HTMLAreaElement#activation_behavior` |
| `lib/dommy/event.rb` | `HashChangeEvent` クラス |
| `lib/dommy/location.rb` | cross-doc→delegate、`reload`、`__internal_set_url__(fire_hash:)`、full-URL hashchange |
| `lib/dommy/history.rb` | push/replace を `fire_hash: false` で |
| `lib/dommy.rb` | `require "dommy/navigation"` |
| `test/test_navigation.rb` | 新規テスト |

**dommy-js-quickjs**:

- `test/fixtures/wpt/html/browsers/browsing-the-web/scroll-to-fragid/…` — 自己完結分を vendor
- `docs/navigation-design.md` — 進捗更新

**触らない(本 PR 範囲外、N2 以降)**:

- driver の `submit_owning_form`、`Browser#click_button`、dommy-rack `Session`/`Navigation`、
  capybara-dommy — フォーム submit 集約は N2。cross-document 文書置換は N3。

---

## 実施順序

```
N0(navigation.rb + Window accessor/__internal_navigate__)  ← rake test green を確認
  → N1-1/2(click 再構成 + EventSynthesis で activation 統一)
  → N1-4/5(HashChangeEvent + pushState 二重発火抑止)         ← 既存 hashchange テスト回帰確認
  → N1-3/6(アンカー follow-the-hyperlink + Location cross-doc 配線)
  → 新規 test_navigation.rb + WPT scroll-to-fragid vendor
最後に dommy/quickjs 両スイート green + bench 回帰なしを確認
```

## リスクと緩和

| リスク | 緩和 |
|---|---|
| synthetic click で activation を足す変更が既存の driver テストを壊す | activation_target が `<a href>` のときだけ発火する設計にし、checkbox/radio/button 経路には触れない。`test_interaction.rb`/`test_browser.rb`/capybara スイートを N1 の一部として green 化 |
| `location.href=` の観測変化 | パーツ更新は従来通り維持し delegate 通知を「追加」するだけ(NullDelegate 既定は記録のみ)。破壊的変更が要るなら CHANGELOG に明記 |
| hashchange の full-URL 化で detail 形が変わる | 既存で `event.detail.oldURL` を bare hash として読むコード/テストがあれば spec 準拠(full URL)に更新 |

## 成功条件(N0+N1)

- [ ] アンカー click(fragment/cross-doc/preventDefault)が spec 通りに振る舞う新規テスト green
- [ ] `location.assign/replace/reload/href=` が cross-doc で delegate に到達、fragment で same-doc
- [ ] HashChangeEvent が real event + full URL、pushState で hashchange 不発火
- [ ] dommy(3339)/ quickjs(596)既存スイート全 green、`script/bench_bridge.rb` 回帰なし
- [ ] WPT scroll-to-fragid の自己完結分が vendor 済み
