// Preprocess a vendored WPT file into a self-contained HTML page: inline
// testharness.js, a result-harvesting report shim, META/script includes, and
// the test body — so jsdom and happy-dom can each run it with no resource loader.
import fs from "node:fs";
import path from "node:path";

const WPT = process.env.WPT;
const TH = fs.readFileSync(process.env.TH, "utf8");

const REPORT_SHIM = `
setup({ output: false, explicit_timeout: false });
globalThis.__wptResults = null;
add_completion_callback(function (tests) {
  globalThis.__wptResults = tests.map(function (t) { return { name: t.name, status: t.status, message: t.message }; });
});
`;

function readMaybe(file) { try { return fs.readFileSync(file, "utf8"); } catch { return null; } }

// Resolve a script src (/-rooted at WPT, else relative to the test dir) to source.
function resolveInclude(spec, testDir) {
  spec = spec.replace(/\?.*$/, "");
  if (spec === "/resources/testharness.js") return TH;
  if (spec === "/resources/testharnessreport.js") return REPORT_SHIM;
  if (spec.startsWith("/resources/testdriver")) return "";
  const file = spec.startsWith("/") ? path.join(WPT, spec) : path.join(testDir, spec);
  return readMaybe(file) ?? "";
}

export function buildPage(rel) {
  const abs = path.join(WPT, rel);
  const src = fs.readFileSync(abs, "utf8");
  const testDir = path.dirname(abs);
  if (rel.endsWith(".html") || rel.endsWith(".htm")) {
    // Inline every <script src=...> (quoted or unquoted attr) with the resolved source.
    const inlined = src.replace(/<script\b[^>]*\bsrc=(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*><\/script>/gi,
      (m, dq, sq, uq) => `<script>\n${resolveInclude(dq || sq || uq, testDir)}\n</script>`);
    return inlined;
  }
  // .any.js / .window.js: wrap like a WPT harness page.
  const metas = [...src.matchAll(/^\s*\/\/\s*META:\s*script=(\S+)/gm)].map(m => m[1]);
  const includes = metas.map(s => `<script>\n${resolveInclude(s, testDir)}\n</script>`).join("\n");
  return `<!DOCTYPE html><html><head>
<script>\n${TH}\n</script>
<script>\n${REPORT_SHIM}\n</script>
${includes}
<script>\n${src}\n</script>
</head><body></body></html>`;
}
