// Rebuild a thrown value as a real Error inside the realm.
//
// QuickJS raises a HOST exception when an evaluated script throws, so by the
// time Ruby sees it the JS value is gone: its name, message and frames survive
// as a Ruby exception, the object itself does not. The page is handed an
// equivalent built here instead, so a handler reading `.message` / `.stack`
// gets what it threw rather than an object with no properties.
//
// `name` is the constructor to use (`TypeError`, …), falling back to `Error`
// for anything the realm does not define. `stack` is already filtered to the
// frames that came from JS — the host's own are not the page's business.
//
// The result is tagged for the bridge here rather than at the call site, so
// crossing back to Ruby carries the object rather than flattening it.
globalThis.__rbDommyRebuildError = function (name, message, stack) {
  var Ctor = globalThis[name];
  var error = new (typeof Ctor === "function" ? Ctor : Error)(message);
  if (stack) {
    try { error.stack = stack; } catch (_) {}
  }
  return __rbHost.tag(error);
};
