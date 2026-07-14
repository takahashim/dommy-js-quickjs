# JS 側イベントオブジェクト設計 (B4 Stage 2)

## 目的

`new CustomEvent(type, init)` は現在 `__rb_construct` で host イベントを作る
(morph 実測で 1514 越境)。construct を JS 側化し、unlistened fast path
(event-dispatch-fastpath.md) と合わせて「誰も聞いていないイベント」の
construct + dispatch を実質 1 越境 (リッスン判定のみ) にする。

## 方針: lazy host materialization + 同一性マッピング

### 1. コンストラクタの JS 側化

`Event` / `CustomEvent` のグローバルコンストラクタを JS 実装に差し替える。
インスタンスは `Object.create(CustomEvent.prototype)`(= B1 で seed 済みの
interface prototype) で作るので、host イベント proxy と `instanceof` /
prototype 同一性が一致する。

init dictionary の変換は JS 側で WebIDL どおりに行う。Event/CustomEvent の
member は boolean 3 つ (`bubbles`/`cancelable`/`composed`) + `detail`(any) だけ
なので再実装コストは小さいが、**WPT は init の member 読み取り順 (辞書順の
Get()) と getter 呼び出しを検査する**ため、変換は own/inherited を問わず
`init.bubbles` 等の Get を辞書順で 1 回ずつ行う実装にする。`type` は
String()、`timeStamp` は `performance.now()`、`isTrusted` false。

状態 (canceled / propagation flags / target / currentTarget / eventPhase) は
JS インスタンスの内部フィールドに置き、prototype の getter
(`defaultPrevented` 等) は「JS イベントなら内部フィールド、host proxy なら
従来どおり host 委譲」に分岐する (インスタンスに own accessor を植える方が
単純: 作成時に defineProperty しておけば prototype 側の分岐は不要)。

MouseEvent / KeyboardEvent 等の派生は対象外 (host construct 継続)。対象は
Event / CustomEvent のみ — フレームワークの名前空間イベントは全てここに入る。

### 2. dispatch

`dispatchEvent(ev)` で ev が JS イベントの場合:

- **fast**: `__rb_host_event_fast?(type)`(新 host 関数、type 文字列を渡すだけ)
  が true (コロン入り + 未リッスン) なら、JS 側で target を設定し
  `!canceled` を返す。**越境はこの判定 1 回だけ**。host イベントは作らない
- **slow**: その場で host イベントを materialize (1 construct 越境。JS 側で
  保持した coerced init から作るので変換の二重適用は起きない) し、
  `hostHandle -> jsEvent` を registry (Map) に登録して従来の dispatch を呼ぶ

### 3. リスナーが受け取るオブジェクトの同一性 (e === ev)

slow path で Ruby がリスナーに渡すのは host イベントの handle。JS 側の
`rehydrate` が handle を proxy 化する前に registry を引き、対応する JS
イベントがあればそれを返す。これで `el.dispatchEvent(ev)` のリスナー引数が
構築時の `ev` と同一になる。

dispatch 中の JS イベントは **live 状態を host に委譲**する:
`preventDefault`/`stopPropagation` は host へ forward、`defaultPrevented`/
`eventPhase`/`currentTarget`/`target` は host から読む (dispatch 中フラグで
分岐)。dispatch 完了後、最終状態 (canceled / target) を JS 内部フィールドに
書き戻して registry から外し、以後は完全に JS 側で答える。

### 4. Ruby 側

- `__rb_host_event_fast?(type)`: event-dispatch-fastpath.md と同じ条件
  (コロン + `EventTarget.__internal_type_listened__?` 否) を bool で返す
- materialize 用は既存の `__rb_construct` をそのまま使う (新規 ABI 不要)

## リスクと検証計画

- **WPT の Event/CustomEvent constructor スイート**が最大の検証対象。init の
  Get 順、getter の例外伝播、`detail` の既定 null、readonly 属性の挙動。
  実装はこのスイートを filter 実行しながら進める
- `document.createEvent("Event")` + `initEvent` 経路は host のまま (対象外)
- Ruby 側が発火するイベント (click 等) は従来どおり host イベント — JS 側
  イベントと混在しても registry は dispatch 中の JS イベントしか持たないため
  干渉しない
- dispatch 中に同じイベントを再 dispatch (spec は InvalidStateError) —
  registry 登録済みなら throw、で spec に合う

## 期待効果

morph (300 行): construct 1514 越境 → 0、fast 判定 1500 のみ残る。
event-dispatch-fastpath と合算でイベント系越境は 4200+ → ~1500。
