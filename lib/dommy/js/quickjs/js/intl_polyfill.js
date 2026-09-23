// This QuickJS build ships without ICU, so `Intl` is undefined and any page
// touching `Intl.NumberFormat` / `DateTimeFormat` / … throws `'Intl' is not
// defined` (nuxt.com, i18n libraries, …). Install a small locale-naive
// polyfill: it formats reasonably (grouped numbers, ISO-ish dates) so pages run
// instead of crashing, without pulling in full ICU.
if (typeof globalThis.Intl === "undefined") {
  var I = {};
  var group = function (s) {
    var p = String(s).split(".");
    p[0] = p[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return p.join(".");
  };
  function NumberFormat(l, o) { this.o = o || {}; }
  NumberFormat.prototype.format = function (n) {
    n = Number(n); var o = this.o;
    if (o.style === "percent") n *= 100;
    var max = o.maximumFractionDigits;
    if (max == null && o.style === "currency") max = 2;
    var s = group(max == null ? String(n) : n.toFixed(max));
    if (o.style === "percent") s += "%";
    if (o.style === "currency" && o.currency) s = o.currency + " " + s;
    return s;
  };
  NumberFormat.prototype.formatToParts = function (n) { return [{ type: "literal", value: this.format(n) }]; };
  NumberFormat.prototype.resolvedOptions = function () { return Object.assign({ locale: "en", numberingSystem: "latn", style: "decimal" }, this.o); };
  function DateTimeFormat(l, o) { this.o = o || {}; }
  DateTimeFormat.prototype.format = function (d) {
    d = d == null ? new Date() : new Date(d);
    if (isNaN(d.getTime())) return "";
    try { return d.toLocaleString(); } catch (e) { return d.toString(); }
  };
  DateTimeFormat.prototype.formatToParts = function (d) { return [{ type: "literal", value: this.format(d) }]; };
  DateTimeFormat.prototype.formatRange = function (a, b) { return this.format(a) + " – " + this.format(b); };
  DateTimeFormat.prototype.resolvedOptions = function () { return Object.assign({ locale: "en", calendar: "gregory", numberingSystem: "latn", timeZone: "UTC" }, this.o); };
  function Collator(l, o) { this.o = o || {}; }
  Collator.prototype.compare = function (a, b) { a = String(a); b = String(b); return a < b ? -1 : a > b ? 1 : 0; };
  Collator.prototype.resolvedOptions = function () { return Object.assign({ locale: "en" }, this.o); };
  function PluralRules(l, o) { this.o = o || {}; }
  PluralRules.prototype.select = function (n) { return Number(n) === 1 ? "one" : "other"; };
  PluralRules.prototype.resolvedOptions = function () { return Object.assign({ locale: "en", type: "cardinal" }, this.o); };
  function RelativeTimeFormat(l, o) { this.o = o || {}; }
  RelativeTimeFormat.prototype.format = function (v, u) { return v + " " + u + (Math.abs(v) === 1 ? "" : "s"); };
  RelativeTimeFormat.prototype.formatToParts = function (v, u) { return [{ type: "literal", value: this.format(v, u) }]; };
  RelativeTimeFormat.prototype.resolvedOptions = function () { return Object.assign({ locale: "en", numeric: "always", style: "long" }, this.o); };
  function ListFormat(l, o) { this.o = o || {}; }
  ListFormat.prototype.format = function (a) { return Array.from(a || []).join(", "); };
  ListFormat.prototype.formatToParts = function (a) { return [{ type: "element", value: this.format(a) }]; };
  ListFormat.prototype.resolvedOptions = function () { return Object.assign({ locale: "en", type: "conjunction", style: "long" }, this.o); };
  I.NumberFormat = NumberFormat; I.DateTimeFormat = DateTimeFormat; I.Collator = Collator;
  I.PluralRules = PluralRules; I.RelativeTimeFormat = RelativeTimeFormat; I.ListFormat = ListFormat;
  ["NumberFormat", "DateTimeFormat", "Collator", "PluralRules", "RelativeTimeFormat", "ListFormat"].forEach(function (k) {
    I[k].supportedLocalesOf = function (locs) { return Array.isArray(locs) ? locs.slice() : locs ? [locs] : []; };
  });
  I.getCanonicalLocales = function (locs) { return Array.isArray(locs) ? locs.slice() : locs ? [String(locs)] : []; };
  globalThis.Intl = I;
}
