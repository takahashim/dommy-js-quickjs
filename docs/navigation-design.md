# Dommy ナビゲーションモデル設計

作成: 2026-07-07 / 更新: 2026-07-08
ステータス: **N0–N3a + N4-1 実装済み**(activation + fragment ナビ + HashChangeEvent + form submit JS API + core Browser の cross-document 文書置換/realm swap + form submission ロジック集約)。N3b(WPT vendor + iframe 共通化)・N4-2(dommy-rack/capybara の delegate 配線)は未着手
関連: `docs/conformance-roadmap.md`(Phase 3/4 の最大宿題)、`docs/dom-library-comparison.md`、
実装詳細 `docs/navigation-impl-N0-N1.md`

## 0. 目的とスコープ

Dommy を「単一ドキュメント内の DOM+JS」から「**ページ遷移を含むセッション**」へ拡張する。
Turbo Drive / Capybara driver / WPT `html/browsers/` 系の 3 つの消費者を同時に満たす
(加えて dommy-tui の dommynx が第4の消費者: 現状 TUI 層で default action を手動再実装
しており、本設計で core に吸収される — §5 N4 参照)。

**前提(明示的な非目標)**: レイアウトエンジンの完全実現は捨てる。したがって
スクロール位置・可視性・幾何に依存するナビゲーション機能は最初から no-op と定義する。
WHATWG navigable モデルの完全実装(bfcache、multi-window、COOP/COEP、Navigation API)も
行わない — 「観測可能な核」だけを spec 準拠で実装する。

## 1. 現状診断(2026-07-07)

### 既にあるもの

| レイヤ | 資産 | 場所 |
|---|---|---|
| セッション(Rack 専用) | `Navigation`: URL 解決・redirect 追従 (307/308)・same-origin 強制・**joint history**(same-doc entry と cross-doc entry の区別)/ `Session#visit/back/forward/reload/get/post…` | `dommy-rack/lib/dommy/rack/navigation.rb`, `session.rb` |
| ページ内 API | `History`: stack+cursor、pushState/replaceState、popstate。**host seam 設計済み** (`__internal_on_change__`, `__internal_go_to__`, `__internal_index__`) / `Location` | `dommy/lib/dommy/history.rb` |
| 文書ブート | `Browser`(resources:, url:, execute_scripts:, settle)+ `ScriptBoot` / WptRunner の iframe 文書置換(fetch→parse→contentDocument→load 発火) | `dommy/lib/dommy/browser.rb`, quickjs `test/support/wpt_runner.rb` |
| クリック合成 | `EventSynthesis.click`(pointer/mouse 全系列、`default_prevented?` を返す) | `dommy/lib/dommy/interaction/event_synthesis.rb` |
| フォーム部品 | form data set の材料(form-owner アルゴリズム、elements、submitter 検証、constraint validation)— B2 作業で spec 準拠化済み | `dommy/lib/dommy/html_elements.rb` |

### 欠けているもの

1. **default action が DOM の外にある**: submit ボタンの activation behavior が
   `Interaction::Driver#click` の `submit_owning_form`(driver 層)に実装されており、
   **JS からの `el.click()` では発動しない**。`<a href>` クリックの activation behavior は
   どこにも無い(イベントが発火するだけ)。
2. **JS 起点のナビゲーションが繋がらない**: `location.href=` / `assign()` / `replace()` /
   `reload()` / `form.submit()` が実ナビゲーションへ到達しない。
3. **core に文書置換パイプラインが無い**(WptRunner が iframe 用に private 実装)。
   Rack なしの埋め込み・WPT `html/browsers/` の検証ができない。
4. dommy-rack の Navigation は Rack 専用で、core の抽象に載っていない(重複の芽)。

**Turbo unit が 52.6% で止まる直接原因** = (1)(2)。Turbo は「リンククリック/フォーム送信の
default action を preventDefault して自前 fetch する」設計なので、**preventable な default
action の存在**と、Turbo が介入しないときの**フォールバック実ナビゲーション**の両方が要る。

## 2. 採用する形: NavigationDelegate ポート

JS ランタイムのプラガブル化(Runtime ポート契約 + レジストリ)と同じパターン。
core は「ナビゲーションの**意図**」を一点に集約し、実行は差し替え可能な delegate に委ねる:

```
発火点(dommy core 内)                     ポート                実装(差し替え可能)
─ <a> click activation behavior ──────┐
─ form submission アルゴリズム ─────────┤                    ① NullDelegate(既定)
─ location.href= / assign / replace ──┼→ NavigationDelegate → ② Browser+Resources(core 内蔵)
─ location.reload / form.submit() ────┤   #navigate(...)     ③ dommy-rack Navigation(既存を接続)
─ history traversal の文書境界越え ─────┤   #traverse(...)
─ (将来) meta refresh / window.open ──┘
```

- **① NullDelegate(既定)**: 実行せず「試行されたナビゲーション」を記録するだけ。
  既存挙動と互換(挙動変更ゼロで導入できる)。単体テストで「navigate が呼ばれたこと」を
  assert する用途にも使う。
- **② Browser+Resources**: core 内蔵の参照実装。`Dommy::Resources` から文書を取得して
  置換する。Rack 無しの埋め込みと WPT `html/browsers/` 検証を可能にする。
- **③ dommy-rack**: 既存 `Navigation` をポート実装へリファクタ(redirect/same-origin/
  cookie は既存ロジックをそのまま活かす)。joint history は core History の seam と接続済み。

### ポート契約(案)

```ruby
# dommy core。Window(または Document)に 1 つぶら下がる。
module Dommy
  module NavigationDelegate
    # クロス文書ナビゲーションの実行。
    #   url:     解決済み絶対 URL(発火点側で base 解決済み)
    #   method:  "GET" | "POST" | ...(form submission 以外は GET)
    #   body:    フォーム送信のボディ(urlencoded/multipart 済み)| nil
    #   headers: 追加ヘッダ(Content-Type 等)
    #   replace: true なら history 置換(location.replace / redirect)
    #   source:  :link | :form | :location | :reload | :traverse(診断・ポリシー用)
    def navigate(url:, method: "GET", body: nil, headers: {}, replace: false, source:)
    end

    # 文書境界を越える history traversal(delta 分)。bfcache は無いので
    # 対象 entry の URL を再フェッチする(= navigate に帰着してよい)。
    def traverse(delta)
    end
  end
end
```

設置場所は `Window#__navigation_delegate__`(writer は embedding 層のみが呼ぶ)。
core の発火点は `document.default_view&.__navigation_delegate__` 経由で到達し、
**nil なら NullDelegate 相当(記録のみ)** にフォールバックする。

## 3. 設計判断(確定事項)

| # | 論点 | 決定 | 根拠 |
|---|---|---|---|
| D1 | **Window/realm の同一性** | 文書置換 = **新 Window + 新 JS realm**(Runtime 作り直し)。Browser/セッションが history・cookie・resources・trace を保持し継続する | **承認済み(2026-07-07)**。ブラウザでも新文書は新 global(WindowProxy の背後で Window は差し替わる)。realm 使い回し+globals 掃除はリーク・汚染リスクが高い。ESM boot ~40-60ms/回はテスト用途で許容。将来 D 戦線(bytecode cache 等)で短縮可能 |
| D2 | **bfcache** | 持たない。back/forward の文書境界越えは**常に再フェッチ** | dommy-rack の現行モデルと一致。文書状態の保存/復元の複雑さを回避(ブラウザの bfcache 無効時と同挙動) |
| D3 | **same-doc / cross-doc の分岐** | fragment のみの変化・pushState/replaceState → **文書維持**(hashchange / popstate / `:target` 更新)。それ以外 → 文書置換 | WHATWG navigate アルゴリズムの観測可能な核。分岐判定は core(発火点側)が行い、delegate には cross-doc だけが届く |
| D4 | **default action の位置** | driver 層の `submit_owning_form` を **core の dispatch(activation behavior)へ移設**。`<a>` の follow-the-hyperlink も activation behavior として新設。いずれも click イベントが preventDefault されたら走らない | JS の `el.click()` / `requestSubmit()` でも発動する必要がある(現状の非互換)。Turbo/フレームワークの介入点として spec 通りの形が必須 |
| D5 | **form submission** | WHATWG form submission アルゴリズムの核を core に実装: submit イベント(cancelable、submitter 付き)→ 非キャンセル時に **form data set 構築**(B2 の部品を再利用)→ method=GET は URL query へ直列化、POST は urlencoded/multipart body → delegate.navigate(source: :form) | Turbo は submit イベントを読むので、イベントの形が spec 通りであること自体に価値がある |
| D6 | **イベント系列** | 新文書: readystatechange → DOMContentLoaded → load(既存 ScriptBoot の系列を再利用)。旧文書: pagehide → unload(発火のみ、beforeunload はイベントのみでダイアログ/中断なし ※将来 policy hook 化余地)。same-doc: hashchange + popstate | 最小限で Turbo/一般フレームワークの期待を満たす |
| D7 | **同一性の継続** | `Browser`(セッション)は生き続ける。`browser.window` は新 Window を指し直す。旧 Window/Runtime は dispose | 消費者(テストコード)は browser/session ハンドルだけ持てばよい |

## 4. スコープ外(捨てるもの)

レイアウト非依存方針とコスト判断により、以下は **no-op / stub / 非実装**と最初から定義:

- スクロール位置の保存・復元(`scrollRestoration` プロパティは既存、動作は no-op)、
  fragment ナビゲーションのスクロール(`:target` 更新のみ行う)
- **bfcache**(D2)/ prerendering / speculation rules
- **beforeunload ダイアログ**(イベント発火のみ、キャンセルによるナビゲーション中断はしない)
- **multi-window**: `window.open` は stub(null か同一 window を返す。将来必要なら別設計)
- **Navigation API**(`navigation.*`): Turbo 8 は History API 利用のため不要。将来検討
- COOP/COEP・cross-origin isolation(same-origin 強制は dommy-rack の既存ポリシーを維持)
- meta refresh・`<base target>`・download 属性のダウンロード実行

## 5. 実装フェーズ

```
N0(ポート導入)→ N1(same-doc 完結)→ N2(form submission)→ N3(cross-doc)→ N4(統合)
```

### N0: ポート定義 + NullDelegate(挙動変更ゼロ)✅ 2026-07-08
- `Dommy::Navigation`(`navigation.rb`)+ `Window#navigation_delegate`(既定 NullDelegate)
  + 集約口 `Window#__internal_navigate__`。NullDelegate は試行を `attempts` に記録。
- 検証: dommy 3353 / quickjs 596 green 維持。

### N1: same-document 完結 + `<a>` activation behavior ✅ 2026-07-08
- `Element#activation_behavior`/`activation_target` hook を新設、`Element#click` を再構成、
  `EventSynthesis.click` でも activation を発火(JS `.click()` と synthetic の両経路統一)。
- `HTMLAnchorElement`/`HTMLAreaElement` に `HyperlinkActivation`(follow-the-hyperlink):
  fragment のみ → `location` の hash 更新 → hashchange + `:target`、それ以外 →
  `__internal_navigate__(source: :link)`。preventDefault で抑止可、download は範囲外。
- `HashChangeEvent`(real event、full old/new URL)を新設し `fire_hashchange` を full-URL 化。
  pushState/replaceState は `fire_hash: false` で hashchange 二重発火を抑止。
- `location.assign/replace/reload/href=` を cross-doc で delegate へ配線(fragment は same-doc)。
- **submit の core 集約(D4 の form 側)は N2 へ遅延**(本 PR では driver/session の submit は不変)。
- 検証: 新規 `test/test_navigation.rb`(14 tests)+ bridge smoke(HashChangeEvent/`:target`/
  fragment click)。WPT `scroll-to-fragid`/`the-location-interface` は scroll・iframe cross-doc
  依存で N1 単体では通せないため vendor 見送り(N3 で再訪)。

### N2: form submission の JS API を delegate へ配線 ✅ 実装済み
- `SubmitEvent`(`submitter` を公開)を新設し、constructor / BASE_CHAINS へ登録
  (`new SubmitEvent("submit", {submitter})` + `instanceof SubmitEvent` 解決)。
- `HTMLFormElement#request_submit(submitter)` → cancelable な `SubmitEvent` を発火し、
  非キャンセルなら `__internal_navigate_for_submit__`。`#submit()` はイベント無しで直行。
- form data set 構築は `Dommy::Interaction::FormSubmission#submit!` を再利用(名前付き有効
  コントロール列挙 / submitter の name/value / disabled・unchecked 除外 — B2 部品)。結果の
  `{method, url, params(順序付き [name,value] 配列), enctype}` を `Window#__internal_navigate__`
  経由で delegate に渡す(直列化は delegate 責務: GET→query / POST→urlencoded・multipart)。
- **範囲**: JS フォーム API(`requestSubmit`/`submit`)のみ。submit ボタン click →
  フォーム submit の click 経路集約(driver の `submit_owning_form` 重複解消)は
  dommy-rack/capybara の delegate 配線と密結合のため **N4 へ集約**(本 PR では既存
  click 経路を一切触らず、4スイート green を維持: dommy 3357 / quickjs 596 /
  dommy-rack 232 / capybara 1259)。
- 検証: `test_navigation.rb` に N2 4件(requestSubmit が SubmitEvent 発火 + params 付きで
  navigate、preventDefault で抑止、submit() はイベント無し、非 submit submitter は TypeError)。
  bridge smoke で `requestSubmit`/`new SubmitEvent`/`e.submitter` を実機確認。
- 今後: WPT `form-submission-0` 系 vendor、Turbo の submit 介入系(N4 で click 集約後)。

### N3a: cross-document 文書置換(core Browser = ポート実装②)✅ 実装済み
- `Dommy::Navigation::Fetcher`(新規): `Resources` アダプタ上の URL 解決 + redirect 追従
  (303→GET / 301・302 POST→GET / 307・308 は method+body 維持)+ GET params の query 畳み込み /
  POST body 直列化。dommy-rack の redirect ループの Resources 版一般化。
- `Dommy::Navigation::JointHistory`(新規): full-doc と same-doc(pushState)を 1 本のスタックに
  持つタブ履歴。各 entry が `(url, window, windex)` を覚え、back/forward が「同一 live 文書の
  popstate 走査」か「文書境界の再フェッチ」かを判定(dommy-rack `Rack::History` の core 版)。
- `Browser` が **自身の NavigationDelegate** になる(`navigable: true` / `Browser.visit(url,
  resources:)`)。既定 `Browser.new(html)` は従来通り NullDelegate(挙動変更ゼロ)。
- 文書置換パイプライン(`perform_navigation!`): fetch(redirect 追従)→ 旧文書 pagehide/unload
  発火(旧 realm 生存中)→ 旧 Runtime dispose → 新 Window parse + Runtime 構築 + ScriptBoot
  (`install_runtime` を初回ブートと共用)→ joint history 更新。**非 document レスポンス
  (JSON 等)/ network miss は現ページ維持**。
- **ナビゲーションはタスク**: JS 起点(`location.href=` / form submit)の delegate 通知は
  即時 swap せず `@pending_navigation` に記録し、次の drain 境界(settle / after_interaction /
  advance_time)で実行(実行中 realm の JS がスタックに載ったまま dispose するのを回避)。
  Ruby 起点(`visit`/`back`/`forward`/`reload`)は即時フラッシュ。
- **in-flight レスポンスの破棄はオーナーシップで自動**: Scheduler は Window 所有・VM/timer は
  Runtime 所有なので、旧 Runtime dispose + 旧 Window 破棄で pending timer/microtask は消滅
  (専用のキャンセル API 不要)。async network の stale-window 対策は N4 で dommy-rack の
  `window.equal?(@current_window)` ガードを踏襲。
- 検証: core `test/test_browser_navigation.rb`(11 tests, `:null` runtime で Ruby 駆動経路)+
  quickjs `test/dommy/js/test_browser.rb` に 2 tests(実 realm swap: fresh realm で再ブート・
  `location.href=` の遅延フラッシュ・旧 realm グローバル非漏洩)。4スイート green
  (dommy 3368 / quickjs 598 / dommy-rack 232 / capybara 1259)。

### N3b: WPT vendor + iframe パイプライン共通化(未着手)
- **WPT `html/browsers/history/the-history-interface`・`the-location-interface`・
  `history-traversal` の自己完結分を vendor**(jsdom も弱い領域: 期待失敗 27〜60/dir)
- WptRunner の iframe 手動 fetch→parse→contentDocument→load 置換ロジックを N3a の
  パイプラインへ寄せる(重複解消)
- same-origin 強制ポリシー(現状 core Browser は test tool として無制限)/ meta refresh 追従

### N4-1: form submission ロジックの集約 ✅ 実装済み
- `HTMLFormElement#__run_form_submission__(submitter)` を新設(cancelable な `SubmitEvent`
  発火 → 非キャンセルなら delegate へ navigation)。`request_submit` もこれを呼ぶ形にリファクタ。
- 従来 bare `Event("submit")` を dispatch していた **4 箇所を集約**: core driver の
  `submit_owning_form` / Enter 暗黙 submit / `Browser#click_button` / capybara `js_submit`。
  いずれも real `SubmitEvent`(submitter 付き)+ delegate 経由に格上げ。
- **navigable Browser は submit ボタン click で実ナビゲーション**するようになった
  (`click_button` → `__run_form_submission__` → delegate)。
- **二重発火なし**: `EventSynthesis` レベルの activation flip はせず、driver が click 後に明示的に
  submission を起こす形を維持(capybara の js_submit も同一メソッド経由に置換)。`el.click()`(JS)
  で submit する完全な activation 化は N4-2 へ。
- 検証: `test_browser_navigation.rb` に 2 tests(click_button で実ナビ / SubmitEvent submitter)。
  4スイート green(dommy 3368 / quickjs 598 / dommy-rack 232 / capybara 1259)。

### N4-2: dommy-rack / capybara の delegate 配線(未着手・リスク評価中)
- dommy-rack `Navigation` をポート実装③にリファクタ(redirect/same-origin/cookie/
  joint history は既存のまま、入口だけポートへ)。SessionRuntime が各 window に delegate を
  attach、JS 起点ナビ(`location.href=`/`form.submit()`)を deferral で受ける(Browser と同じ機構)。
- capybara-dommy: `click_link` / `js_submit` の特殊処理を実クリック(activation → delegate)に置換
- **dommynx(dommy-tui、第4の消費者)**: `App#activate_link` の
  「prevented でも navigated でもなければ href を follow」フォールバック
  (`app.rb:1107` 付近)は core activation behavior の手動再実装なので、delegate ③接続後は
  **二重ナビの芽 → 同一マイルストーンで削除**。dommynx の UX ポリシー(SPA in-place route を
  信用せず full_visit、ナビ開始時の集計リセット)は dommynx 自前の delegate 実装④として
  表現できる(クリック前後の URL 差分検出を明示的な navigate 通知へ置換)
- 検証: **Turbo スイート 20/38 → 目標 ~100%(unit)**、dommy-rack/capybara-dommy/
  dommynx の既存スイート green、Stimulus 210/214 維持

## 6. リスクと緩和

| リスク | 緩和 |
|---|---|
| activation behavior の core 移設で既存テスト(driver 経由の submit)が二重発火 | N1 で driver 側を同時に削除し、dommy/dommy-rack/capybara-dommy の 3 スイートを同一 PR で green にする |
| 新 realm 化で「navigate 後も前の JS 状態が見える」ことに依存した既存利用が壊れる | dommy-rack は既に文書再構築モデルなので影響は限定的。Browser 直接利用者向けに CHANGELOG に明記 |
| ~50ms/navigation のコスト | テスト用途では許容(D 戦線の ESM bytecode cache で将来短縮)。ベンチに visit 系を追加して回帰監視 |
| WPT html/browsers はナビゲーション以外(実 iframe・cross-origin)依存も多い | vendor 時に自己完結分を選別(既存の運用ルール通り、drop 理由を記録) |

## 7. 成功条件

- [ ] N0-N2: Turbo unit の link/submit 介入系が green(52.6% から大幅増)
- [ ] N3: WPT `html/browsers/history` 系の自己完結分で jsdom 同等以上
- [ ] N4: **Turbo unit ~100%**、capybara-dommy で「visit → click_link → 遷移 → back」の
  実フローがドライバ特殊処理なしで通る
- [ ] 全期間: dommy/quickjs/dommy-rack/capybara-dommy の既存スイート green 維持、
  `script/bench_bridge.rb` に回帰なし
