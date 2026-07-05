// Static get_host_info for the single-VM WPT harness. The document loads at
// http://<host>/… and the vendored resource layer serves every path regardless
// of host, so a distinct host / scheme is a genuinely cross-origin URL that
// still resolves to the same endpoints — enough to exercise the fetch CORS
// mode checks (same-origin / cross-origin) without a real multi-origin server.
function get_host_info() {
  const loc = self.location;
  const host = loc.hostname || "localhost";
  const httpPort = loc.port && loc.protocol === "http:" ? ":" + loc.port : "";
  const remoteHost = host === "localhost" ? "127.0.0.1" : "www1." + host;
  const altPort = "8001";
  const HTTP_ORIGIN = "http://" + host + httpPort;
  const HTTPS_ORIGIN = "https://" + host;
  const HTTP_REMOTE_ORIGIN = "http://" + remoteHost + httpPort;
  const HTTPS_REMOTE_ORIGIN = "https://" + remoteHost;
  return {
    HTTP_ORIGIN, HTTPS_ORIGIN, HTTP_REMOTE_ORIGIN, HTTPS_REMOTE_ORIGIN,
    ORIGINAL_HOST: host, REMOTE_HOST: remoteHost,
    HTTP_PORT: loc.port || "80", HTTPS_PORT: "443",
    HTTP_ORIGIN_WITH_DIFFERENT_PORT: "http://" + host + ":" + altPort,
    HTTP_REMOTE_ORIGIN_WITH_DIFFERENT_PORT: "http://" + remoteHost + ":" + altPort,
    HTTPS_ORIGIN_WITH_DIFFERENT_PORT: "https://" + host + ":" + altPort,
  };
}
