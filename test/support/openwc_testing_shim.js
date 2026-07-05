// esbuild aliases `@open-wc/testing` to this module when bundling Turbo's unit
// suite (see script/build_turbo_tests.sh). The real package pulls in chai +
// lit-html + a11y helpers; Turbo's unit tests only import `assert`, which
// test/support/mocha_shim.js installs on globalThis before the bundle runs.
export const assert = globalThis.__assert
