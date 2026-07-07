# Dommy Conformance ロードマップ — 振り返りと今後の進め方

作成: 2026-07-07
対象: dommy gem (`/Users/maki/git/dommy`) + dommy-js-quickjs
目的: **「Dommy が十分に conformance の高いライブラリである」と言える状態**への道筋を定義する。

---

## 1. 現在地 (2026-07-07 実測)

```
WPT conformance: 43581/43924 subtests (99.2%) across 384 files; 319 files fully green

  FileAPI     256/260   (98.5%)
  accname     300/303   (99.0%)
  css        3935/3985  (98.7%)
  dom       33771/33932 (99.5%)
  domparsing   98/100   (98.0%)
  encoding    187/191   (97.9%)
  fetch       264/286   (92.3%)
  html       1636/1682  (97.3%)
  url        1395/1397  (99.9%)
  wai-aria    387/389   (99.5%)
  webstorage 1172/1200  (97.7%)
  xhr         180/199   (90.5%)
```

フレームワーク実戦スイート:
- Stimulus 公式 QUnit: **210/214 (98.1%)**
- Turbo 公式 (unit のみ移植可): **20/38 (52.6%)**

性能 (戦線D): セレクタ AST キャッシュ済 (matches? 8.5x)。ベンチ基盤 `script/bench_bridge.rb` 常設。

### 軌跡

| 時点 | 合格/分母 | 率 | 備考 |
|---|---|---|---|
| 第1トランシェ前 | 37037/37800 | 98.0% | iframe ナビ未対応で ~2000 subtests が分母落ち |
| 第1トランシェ後 | 40173/40443 | 99.3% | harness iframe 修正 + nodeValue 等 |
| **現在** | **43581/43924** | **99.2%** | 分母 +3481 を **~98% 合格で吸収** |

**重要な読み方**: 率はほぼ横ばいだが、分母を 3500 増やしながら率を維持した。
これは「新領域を vendor しても最初から 9 割以上通り、残りをコード修正で
green 化できる」成熟度に達したことを意味する。

---

## 2. 振り返り — 何が効いたか

### 2.1 成功パターン(今後も繰り返す作業ループ)

```
1. WPT からテスト群を vendor(共通 include も忘れず)
2. rake wpt:conformance[filter] で計測
3. 失敗を分類:
   a. dommy 本体のバグ/未実装  → root cause を修正(最優先)
   b. bridge 層の不足           → host_runtime.js / host_bridge.rb に汎用機構を追加
   c. harness の制約            → wpt_runner を改善 or 制約として記録
   d. 環境依存 (testdriver 等)  → drop して記録
4. 両スイート (dommy 3339 / quickjs 596) の回帰ゼロを確認
5. dommy 側 feat コミット + quickjs 側 vendor コミットのペア
6. compat-roadmap-todo.md に追記(コミットしない)
```

### 2.2 レバレッジの高かった投資(1つの修正が広域に波及)

| 投資 | 波及先 |
|---|---|
| `value_as_number`(7型の日付⇄数値変換) | valueAsNumber 64/64、stepUp/Down 58/58、constraint validation 全域 |
| option の selectedness/dirtiness モデル | option 44/44 → select 42/42 に波及 |
| 検証済み挿入 (`insert_before`/`append_child` 経由化) | cycle 検出 + 異 document adoption がテーブル全域に |
| イベントリスナ `this`=currentTarget | 全フレームワークの非アロー関数ハンドラ |
| bridge: indexed setter / LegacyOverrideBuiltIns / READONLY_ATTRS | select・form・template、今後の全インターフェース |
| harness: UTF-8 BOM strip / iframe ナビ / 共通 include vendor | 以後の vendor 全部(template-content 0→216 の例) |
| namespace 判定の strict 化(null-ns ≠ HTML) | table/tr/option/rows、今後の全要素 |

**教訓**: 「テストを1本通す」より「そのテストが要求している *仕様上の
メカニズム* を実装する」方が、必ず後で他のテストも通す。

### 2.3 落とし穴(再発防止)

- **0/0 は include 不足のサイン**: `common.js` / `validator.js` / `.js` 相対 include を先に確認
- **404/429 エラーページの vendor 事故**: fetch 後に必ずサイズ/先頭バイト確認(`head -c 20`)
- **偶然パスしていたテスト**: input.maxLength= が属性未反映で tooLong が偶然 green だった類。
  修正時は「なぜ今まで通っていたか」も確認する
- **PATH を export しない**(mise 環境を壊す)
- **仕様の細部は WPT が正**: 「tooLong は user edit 時のみ」「radio group は tree scope」など、
  MDN の要約ではなく WHATWG アルゴリズムの step を読む

---

## 3. 「十分に高い」の定義(ゴール基準)

conformance は率だけでは語れない。**3軸**で定義する:

| 軸 | 指標 | 現在 | 目標 |
|---|---|---|---|
| **深さ** | vendored corpus の合格率 | 99.2% | **≥99.5%**、errored 0 維持 |
| **広さ** | 分母(実行 subtests 数)と領域カバレッジ | 43.9k / 主要領域に穴 | **~60k+**、下記「未開拓領域」を解消 |
| **実戦** | フレームワーク公式スイート | Stimulus 98%, Turbo 53% | Stimulus/Turbo(unit) **~100%**、+2 フレームワーク追加 |

**競合との比較基準**: jsdom / happy-dom が公開している WPT 結果と、領域が重なる
ディレクトリ単位で比較し「同等以上」を確認する(→ Phase 0 のタスク)。

---

## 4. ロードマップ

### Phase 0: 基準線の確定 ✅ (2026-07-07 完了)

- [x] jsdom の to-run.yaml(103 dirs)分析 + 我々の corpus での 3-way 再測定
      → `docs/dom-library-comparison.md` の 2026-07-07 節
- [x] happy-dom は WPT を体系実行していないことを確認(公開レポート無し)
- [x] `docs/wpt-conformance.md` に 2026-07-07 スナップショット(43581/43924)を記録
- [x] 優先順位を Phase 1/2 に反映(下記)

**Phase 0 の主要な発見:**
1. **深さ: fully-green 319 vs jsdom 236 vs happy-dom 91**(我々の 384 ファイル corpus)。
   jsdom に負けている実項目は **14 ファイル・~40 subtests** に特定(比較 doc の表)
2. **広さ: jsdom が 53 dirs 先行**。うち custom-elements(jsdom 64+24 fails)と
   shadow-dom(43 fails)は jsdom 自身が弱く、Dommy は実装済み → **差別化チャンス**
3. **patternMismatch の `v`-mode 正規表現は won't-fix から昇格候補**:
   Ruby Regexp でなく **QuickJS 側の JS RegExp に pattern 評価を委譲**すれば解ける
4. webstorage lone surrogate は jsdom には存在しないギャップ(JS ネイティブ文字列)。
   解消には QuickJS 側に文字列を保持する設計変更が要る(コスト大、当面保留)

### Phase 1: 既存 corpus の残欠陥掃討(合格率 99.2% → 99.5%+)

残 343 fail の分類と対処。**コードのみで進められる(レート制限の影響なし)**:

| 領域 | 残 | 内訳と対処 |
|---|---|---|
| dom (161) | ★最大 | createElementNS の Makiri XML name 66(**Makiri 側修正** or dommy 側 pre-validation)/ reflection.js ブリッジ往復タイムアウト(→ Phase 3 D2)/ その他個別 |
| xhr (19) | ★率最低 | 90.5%。エンドポイント emulation の未対応ケースを詰める |
| fetch (22) | ★率次点 | 92.3%。CORS/redirect の残ケース |
| css (50) | | cascade/計算値の個別バグ |
| html (46) | | v-mode 正規表現 11(**won't-fix**: Ruby 非対応)、past-names map、parser-time details 排他、toggleEvent 残 2 など |
| webstorage (28) | | lone surrogate ~24 は **won't-fix**(Ruby 文字列で表現不能)。prototype identity 2 は D2 で |
| encoding (4) / domparsing (2) / FileAPI (4) | | 個別。FileAPI は stream() 未実装 |

- [ ] まず xhr → fetch(率が低い = 伸び幅が大きい)
- [ ] dom の Makiri XML name 66 を解消(単一原因で最大のかたまり)
- [ ] **jsdom-green ギャップ 14 ファイル**(比較 doc の表)を優先的に潰す — 特に
      patternMismatch は QuickJS RegExp('v') 委譲で解ける見込み
- [ ] won't-fix を `docs/wpt-conformance.md` に明記し、分子の実質上限を定義

### Phase 2: 分母拡大・第2トランシェ(43.9k → ~60k)

未開拓領域を、**フレームワーク需要の高い順**に vendor する:

1. **shadow-dom/**(B1)— Lit/Web Components 系の前提。ブリッジ hardening と対
2. **custom-elements/**(B1)— 同上。Dommy は実装済みなので「計測して穴を潰す」フェーズ
3. **selection/** — Selection API。エディタ系(Trix/ProseMirror)の前提
4. **html/webappapis/** — base64 (atob/btoa)、structured clone、timers、microtask。
   フレームワークが直接叩く基盤 API 群
5. **html/semantics の残り** — embedded-content(iframe/img の DOM API 面)、
   sections、interactive-elements の残り、edits (ins/del)
6. **html/dom/**(reflection.js を除く大物)— aria-attributes、document metadata
7. **streams/** の runnable 部分、**urlpattern/**(実装があれば)、**hr-time/** の基本

見積り regime: このセッションの実績では、1領域 = 半日〜1日で
「vendor → 90%+ → 個別修正で green 化」まで到達できる。

- [ ] 各領域 vendor 時に、0/0 ファイルの include 依存を先にまとめて vendor する
- [ ] GitHub レート制限対策: `git clone --depth 1 --filter=blob:none --sparse` で
      WPT リポジトリの部分 checkout をローカルに持ち、raw fetch をやめる(★推奨)

### Phase 3: 基盤投資(点でなく面を解放する)

Phase 1/2 の過程で必要になる、単体で価値の大きい機構:

- [ ] **D2: ブリッジ高速化**(compat-roadmap-todo.md 戦線D と同一投資)
      → reflection.js のタイムアウト解消 = html/dom/reflection-* の巨大分母が解放される
- [ ] **JS Date ⇄ Ruby Time の双方向 marshaling**
      → input.valueAsDate(30+ subtests)、将来の File.lastModifiedDate 等
- [ ] **WebIDL stringifier branding**(toString の brand check)
      → a-stringifier 等。優先度低、機構としては小さい
- [ ] **harness: 動的 document 生成対応**(`newHTMLDocument()` = createHTMLDocument ベース、
      iframe contentWindow.document)→ template/content-attribute の残り等
- [ ] **testdriver の最小 emulation**(send_keys → value 設定+input/change 発火、
      click → dispatchEvent)は費用対効果を見て判断。真の UI 忠実性は目的でないため、
      「emulate できる範囲」を明確に区切る

### Phase 4: 実戦検証(WPT の外側)

WPT が green でも実アプリで壊れるなら意味がない。逆方向の検証を並走:

- [ ] **Turbo unit の残り 18** を解消(52.6% → 100% が目標。visit/navigation 系は
      対象外と明記する)
- [ ] **Stimulus 残り 4** の解消
- [ ] 新フレームワークスイートの追加(優先順): **htmx** → **Alpine.js** → **Lit**
      (Lit は shadow-dom/custom-elements の Phase 2 完了後)
- [ ] capybara-dommy / dommy-rack 統合シナリオでの smoke test
      (モノレポ統合の進行と同期)

### Phase 5: 性能並走(conformance と交互に)

conformance 作業で DOM が重くなっていないかを常時監視:

- [ ] 大きな feat コミット群の後に `script/bench_bridge.rb` を実行し、
      compat-roadmap-todo.md 戦線Dの表と比較(**回帰ゲート**)
- [ ] 残ホットスポット: style_generation 単一エポック / MutationCoordinator の
      無条件 subtree walk / ESM boot 40→62ms
- [ ] 特に注意: 今回導入した live collection(labels / RadioNodeList / rows)は
      アクセス毎に再計算する。ホットパスに乗ったらキャッシュ+世代タグ化を検討

---

## 5. 実行順序とマイルストーン

```
Phase 0 (基準線)                          … 半日
   ↓
Phase 1 (掃討) ←──────┐                  … 1〜2週
   ↓                   │ 交互に
Phase 2 (第2トランシェ) ┘                 … 2〜4週
   ↓          随時 Phase 3 (基盤) を差し込む
Phase 4 (実戦検証)                        … Phase 2 後半から並走
Phase 5 (性能) は各 Phase の区切りで必ず計測
```

| マイルストーン | 判定条件 |
|---|---|
| **M1: 深さ達成** | vendored 99.5%+、xhr/fetch が 97%+、won't-fix 一覧が文書化済み |
| **M2: 広さ達成** | shadow-dom/custom-elements/selection/webappapis vendor 済みで全体 98.5%+、分母 60k+ |
| **M3: 実戦達成** | Stimulus/Turbo(unit) ~100%、htmx or Alpine スイート 95%+ |
| **M4: 競合比較** | jsdom/happy-dom と重なる領域で全ディレクトリ同等以上 |

**M1〜M4 をすべて満たした時点で「Dommy は十分に conformance の高いライブラリ」と宣言できる。**

---

## 6. 運用ルール(このセッションで確立したもの)

1. ベースライン厳守: dommy `bundle exec rake test`(3339)と quickjs(596)を
   変更のたびに回し、**回帰ゼロでのみコミット**
2. コミットは dommy 側 `feat`/`fix` + quickjs 側 `test(wpt): vendor` のペア
3. `docs/compat-roadmap-todo.md` は更新するがコミットしない(このファイルの扱いは指示に従う)
4. vendor 品質: 404/429/BOM/reftest/testdriver 依存を検知したら即 drop し、理由を記録
5. 各領域は「dir 単位で green」を完了条件とする(ファイル単位のつまみ食いにしない)
