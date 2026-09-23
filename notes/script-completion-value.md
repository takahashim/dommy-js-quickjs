# スクリプトの完了値が Promise だとページがエラーを受け取る

## 症状

dommy-conformance の WPT コーパスで、`html/semantics/interactive-elements/the-details-element/toggleEvent.html` が **11/11 から 0/0 に落ちた**。

落ちた時点は dommy 側の「未処理例外をグローバルで報告する」一連の変更（`a6a897a` から `d34d48d`）である。
このファイルのテストは11件とも登録されているのに、結果が1件も報告されずにハーネスが完了する。
そのため pass/total が 0/0 になり、`rake wpt` は後退として検出する。

quickjs の fork（`takahashim/quickjs.rb` の `ef60ed5`）を使っても直らない。
fork で直るのは `dom/observable/tentative/observable-from.any.js` の2件（31/48 から 33/48）だけである。

## 機構

このページは2本のインラインスクリプトを持ち、1本目が次の形で終わる。

```html
<script>
  window.details9TogglePromise = new Promise(resolve => {
    window.details9TogglePromiseResolver = resolve;
  });
</script>
```

代入式が最後の文なので、スクリプトの完了値は Promise になる。
`Runtime#load_script` は完了値を捨てずに eval する。

```ruby
def load_script(js)
  bump_dom_epoch
  @backend.eval(js)      # 完了値が pending な Promise
  drain_microtasks
  nil
end
```

quickjs gem はこれを「top-level に未 await の Promise が返された」と判定し、Ruby 例外 `Quickjs::RuntimeError` を上げる。
その例外は `ScriptBooter#run_one` に捕まり、`report_exception` がページの `window` にエラーとして報告する。
testharness の `window.onerror` はこれを受けてハーネス全体の status を ERROR にし、個々のテストの結果を報告しないまま完了する。

つまり、11件のテストは登録も実行もされているのに、ハーネスがそれらを報告する前に打ち切られる。

`load_script` から報告に至る経路は、失敗時のバックトレースがそのまま示している。

```
Quickjs::VM#eval_code            (backend.rb:82)
Dommy::Js::Quickjs::Backend#eval (backend.rb:82)
Dommy::Js::Quickjs::Runtime#load_script (runtime.rb:133)
Dommy::Js::ScriptBooter#run_pending     (script_boot.rb:270)
Dommy::Js::ScriptBooter#run_one         (script_boot.rb:260)
```

ブラウザでは、classic script の評価結果はどこにも使われず捨てられる。
完了値が Promise であることはエラーではないので、この症状はエンジン埋め込み側の都合がページから見えてしまっている状態である。

## 同じ配慮が他の経路には入っている

`Runtime` の他のメソッドは、すでにこの検査を避けている。

- `execute`：スクリプト全体を IIFE で包み、完了値を消している（コメントに「otherwise a trailing Promise expression would trip the gem's "unawaited Promise" guard」と明記されている）
- `evaluate_settled`：`globalThis.__rbEvalP = Promise.resolve(...); void 0;` と書き、`void 0` で完了値を Promise から外している

`load_script` はグローバルスコープを保つ必要があるため IIFE では包めない。
その制約のもとで完了値だけを捨てる手当てが抜けている。

## 修正案

`load_script` に渡すソースの末尾に、完了値を消す文を足す。

```ruby
def load_script(js)
  bump_dom_epoch
  @backend.eval("#{js}\n;void 0;")
  drain_microtasks
  nil
end
```

手元で dommy-conformance のランナーからこの形に差し替えると、`toggleEvent.html` は 11/11 に戻った。
リリース版の quickjs 0.21.0 でも fork の `ef60ed5` でも同じ結果になる。

先頭に改行を挟むのは、元のソースが行コメントで終わる場合に `void 0` がコメントに吸われないようにするためである。
グローバルスコープは保たれるので、`var` や `function` の宣言がグローバルになる性質は変わらない。

## 併せて確認したい点

- **`load_script_cached`**：バイトコードを経由するが完了値の扱いは同じである。同じ手当てが要るか確認したい。
- **`run_module` の経路**：ES モジュールは完了値を持たないため影響しないと見込んでいるが、未確認である。
- **ページが本当に throw した場合との切り分け**：スクリプトが実際に例外を投げたときは、これまでどおりページに報告されなければならない。上の修正は完了値だけを捨てるので、throw の報告は変わらないはずである。回帰テストを足すなら、完了値が Promise のスクリプトと、末尾で throw するスクリプトの両方を見るとよい。

## もう一つの問題：ページから Ruby のバックトレースが読める

`ErrorEvent` の `error.stack` が Ruby のバックトレースになっている。

```
Quickjs::VM#eval_code (backend.rb:82)
Dommy::Js::Quickjs::Backend#eval (backend.rb:82)
...
Dommy::Js::ScriptBoot.run_document_scripts (script_boot.rb:34)
```

`rebuild_error` が Ruby 例外の `backtrace` をそのまま JS の `stack` に埋めているためである。

```ruby
var stack = #{::JSON.generate(Array(error.backtrace).join("\n"))};
```

JS 由来の例外なら `backtrace` は JS のフレームなので、この実装で正しい。
ホスト側で発生した Ruby 例外では、ホストのファイルパスがページから読めてしまう。
dommy は `ErrorEvent#filename` について、エンジン内部の名前を document の URL に差し替える処理を持っている（`internal/exception_report.rb` の `ANONYMOUS_SOURCES`）。
`stack` にも同じ趣旨の切り分けが要る。
Ruby のフレームしか無いときは `stack` を空にするか、JS のフレームだけを残すのが素直だと考える。

あわせて、このとき `ErrorEvent#lineno` は 0 になっていた。
JS の位置情報が無いので当然ではあるが、ブラウザなら document の URL と行番号が入る場所である。

## 再現手順

dommy-conformance で、dommy と dommy-js-quickjs の worktree を指して1ファイルだけ走らせる。

```sh
cd dommy-conformance
DOMMY_PATH=/path/to/dommy/gems/dommy \
DOMMY_JS_QUICKJS_PATH=/path/to/dommy-js-quickjs \
  bundle exec ruby runner/wpt.rb --filter the-details-element/toggleEvent --out /tmp/t.jsonl
```

修正前は 0/0、修正後は 11/11 になる。

`window` に届いているエラーそのものを見るには、テストページの `testharnessreport.js` の直後に `window.addEventListener("error", ...)` を挟み、`e.message`、`e.error.stack`、`e.lineno` を読むとよい。

## dommy-conformance 側の状態

- Gemfile に quickjs の fork（`ef60ed5`）を固定する変更を入れた。これが無いと `observable-from.any.js` が 31/48 になり、dommy-js-quickjs が前提としているエンジンとは別のエンジンを測ることになる。
- ベースラインの更新は `toggleEvent.html` が戻ってから行う。現在の差分はこの1ファイルだけである。
