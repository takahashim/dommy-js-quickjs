# Unlistened-event dispatch fast path (B4)

## 問題

Turbo 8 の morph は要素ごとに `turbo:before-morph-element` などの CustomEvent を
construct → dispatch → `defaultPrevented` 読み、を行う。300 行の morph 実測
(`script/profile_real_app.rb`) で CustomEvent construct 1514 + dispatchEvent 1500 +
defaultPrevented 1207 の越境に加え、**dispatch のたびの保守的 epoch バンプが全 JS
キャッシュ (属性スナップショット / stable props / length) を無効化**し、後続の
再フェッチ越境 (~5000) を誘発していた。ほぼ全ての dispatch は「誰もリッスンして
いない」ので、この全てが空振りのコストである。

## 設計

判定と実行を 1 往復に融合した host 関数を追加する。

```text
__rb_host_dispatch_fast(target_handle, event_handle)
  -> {fast: true, result: bool}   # 高速経路が成立し、dispatch 済み
  -> {fast: false}                # 不成立。JS 側が従来経路へフォールバック
```

Ruby 側の成立条件は次の 2 つで、どちらも Ruby が権威を持つ。

- **type がコロン (`:`) を含む** — 組み込みのデフォルトアクション (click の
  activation、summary の details toggle 等) を持つ type にコロン入りは存在しない。
  フレームワークの名前空間イベント (`turbo:*`, `app:*`) だけが対象になる
- **その type のリスナーがプロセス内に一つも登録されたことがない** —
  `Dommy::EventTarget` の**追加専用** type レジストリ (add_event_listener が記録) で
  判定する。追加専用なので remove との対応付けバグが原理的に起きない
  (解除済み type は過剰に「リッスン中」と見なされ、fast を失うだけで正しさは保つ)

成立時は Ruby の通常の dispatch 機構をそのまま実行する (リスナーゼロなので
propagation は何も呼ばない) ため、target / eventPhase / canceled の意味論は
従来と完全に同一である。返り値 `result` は dispatchEvent の返り値 (= !canceled)。

## JS 側

- `dispatchEvent` の専用メソッドラッパーが `__rb_host_dispatch_fast` を先に呼ぶ。
  `fast: true` なら **epoch バンプなし**で `result` を返す — リスナーゼロ +
  デフォルトアクションなしなら DOM 変異は起き得ないので、キャッシュは無傷でよい。
  `fast: false` なら従来どおり bump + `dispatchEvent` 越境
- fast 成立後、event proxy に own-prop `defaultPrevented` shadow (= `!result`) を
  植える。morph が dispatch 後に読む `defaultPrevented` の越境が消える。
  get trap は own property を最優先で返すので追加の分岐は不要
- `preventDefault` の専用ラッパーが呼び出し前に shadow を delete する
  (dispatch 後の preventDefault でも defaultPrevented が正しく true を返す)。
  preventDefault は event の canceled フラグしか変えないので epoch バンプも外す

## 同期問題が存在しない理由

JS 側にリスナー表のミラーを持つ案は、Ruby 側リスナー追加 (テストコード、Ruby
custom element のコールバック) との同期プロトコルが必要になり、host 呼び出しの
たびに dirty 化する保守設計では morph の行ごとに再同期越境が復活する。判定を
Ruby に置けば、レジストリは常に最新で、staleness という概念自体が消える。
コストは fast 不成立時の 1 越境追加 (colonless / リッスン済み type の dispatch)
だが、これらはもともと bump + dispatch + リスナー実行のコストが支配的である。

## 将来 (Stage 2)

construct 側 (CustomEvent 1514 越境) を消すには event オブジェクトの JS 側化が
必要だが、slow path でリスナーが受け取る event の同一性 (`e === ev`) を保つには
dispatch 時の host 具現化では足りない。JS 側 event を正とし Ruby 側 dispatch が
JS event を参照する反転が要る — bridge-redesign.md の領域として据え置く。
