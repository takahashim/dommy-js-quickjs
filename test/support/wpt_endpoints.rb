# frozen_string_literal: true

require "cgi"
require "uri"

module Dommy
  module Js
    # Wraps a Resources adapter to apply the wptserve `?pipe=` query — the
    # substitution WPT uses to shape a static resource's response inline. The
    # pipe is stripped from the URL before the inner adapter resolves it (so a
    # file / endpoint sees its real path + other params), then applied to the
    # Response. Supports `header(name,value)` (add a response header) and
    # `status(code)`, chained with `|` — enough for the CORS tests
    # (`top.txt?pipe=header(Access-Control-Allow-Origin,*)`).
    class WptPipe
      def initialize(inner)
        @inner = inner
      end

      def get(url, headers: {}) = request(method: "GET", url: url, headers: headers)

      def request(method:, url:, headers: {}, body: nil)
        pipe, clean_url = extract_pipe(url)
        response = @inner.request(method: method, url: clean_url, headers: headers, body: body)
        return response if response.nil? || pipe.nil?

        apply(response, pipe)
      end

      private

      # Pull `pipe=…` out of the query, returning [pipe_string_or_nil, url_without_pipe].
      def extract_pipe(url)
        uri = URI.parse(url.to_s)
        params = (uri.query || "").split("&")
        pipe_param = params.find { |p| p.start_with?("pipe=") }
        return [nil, url] unless pipe_param

        uri.query = (params - [pipe_param]).join("&")
        uri.query = nil if uri.query.empty?
        [CGI.unescape(pipe_param.delete_prefix("pipe=")), uri.to_s]
      rescue URI::InvalidURIError
        [nil, url]
      end

      def apply(response, pipe)
        pipe.split("|").each do |command|
          m = command.match(/\A(\w+)\((.*)\)\z/)
          next unless m

          case m[1]
          when "header"
            name, value = m[2].split(",", 2)
            (response.headers ||= {})[name.strip] = value.to_s
          when "status"
            response.status = m[2].to_i
          end
        end
        response
      end
    end

    # A `Dommy::Resources` adapter that emulates the handful of dynamic WPT
    # server endpoints (`resources/*.py`) the fetch / xhr suites hit — the ones a
    # real WPT run answers with wptserve handlers. It implements the same
    # `#request(method:, url:, headers:, body:)` -> `Resources::Response | nil`
    # contract as the built-in adapters, so it drops straight into
    # `WptResources.build`'s chain (ahead of the file_system adapter, which serves
    # the static tree). An unrecognized path returns nil and falls through.
    #
    # Only the behavior the vendored tests exercise is implemented; each endpoint
    # mirrors its wptserve script's contract (status.py, …). Grow this as more
    # fetch/xhr tests are vendored.
    class WptEndpoints
      def initialize
        # Server-side "stash" keyed by the tests' per-request token — one WptEndpoints
        # lives for a whole test file, so a token set by one request (e.g. a
        # recorded preflight) is visible to a later one, as wptserve's stash is.
        @stash = {}
      end

      def get(url, headers: {}) = request(method: "GET", url: url, headers: headers)

      def request(method:, url:, headers: {}, body: nil)
        uri = parse(url)
        return nil unless uri

        case ::File.basename(uri.path)
        when "status.py" then status_py(uri, url)
        when "inspect-headers.py" then inspect_headers_py(uri, headers, url)
        when "redirect.py" then redirect_py(uri, url)
        when "redirect-empty-location.py" then redirect_empty_location_py(url)
        when "clean-stash.py" then clean_stash_py(uri, url)
        when "preflight.py" then preflight_py(method, uri, headers, url)
        when "content.py" then content_py(uri, body, url)
        when "echo-content-type.py" then echo_content_type_py(headers, url)
        end
      end

      private

      def parse(url)
        URI.parse(url.to_s)
      rescue URI::InvalidURIError
        nil
      end

      # wptserve resources/status.py: echo an arbitrary status line, content type,
      # and body straight from the query — `?code=&text=&type=&content=`. `content`
      # and `type` are percent-encoded; `content` carries raw response bytes.
      def status_py(uri, url)
        q = query(uri)
        code = (q["code"] || "200").to_i
        text = q["text"] || "Yes"
        type = q["type"]
        content = q["content"] || ""
        headers = {}
        headers["Content-Type"] = type unless type.nil? || type.empty?
        ::Dommy::Resources::Response.new(
          status: code, status_text: text, headers: headers,
          body: content, url: url.to_s, redirected: false
        )
      end

      # wptserve resources/inspect-headers.py: reflect chosen request headers
      # back so a test can assert what was sent — `?headers=Name1|Name2`. For each
      # present request header it adds a response header `x-request-<name>` with
      # that header's value. `headers:` reaches here as a lowercased-name Hash.
      def inspect_headers_py(uri, req_headers, url)
        req = (req_headers || {}).transform_keys { |k| k.to_s.downcase }
        out = {}
        (query(uri)["headers"] || "").split("|").each do |name|
          key = name.strip.downcase
          out["x-request-#{key}"] = req[key] if req.key?(key)
        end
        out["Access-Control-Allow-Origin"] = "*"
        ::Dommy::Resources::Response.new(
          status: 200, status_text: "OK", headers: out, body: "", url: url.to_s, redirected: false
        )
      end

      # wptserve resources/redirect.py: a raw 3xx redirect — `?redirect_status=`
      # (default 302) and an optional `?location=` (the Location header). The fetch
      # polyfill does the following itself (mode follow/manual/error), so this just
      # returns the redirect response unfollowed.
      def redirect_py(uri, url)
        q = query(uri)
        status = (q["redirect_status"] || q["status"] || "302").to_i
        location = q["location"]
        ::Dommy::Resources::Response.new(
          status: status, status_text: "", headers: location ? {"Location" => location} : {},
          body: "", url: url.to_s, redirected: false
        )
      end

      # wptserve resources/redirect-empty-location.py: a 302 whose Location header
      # is present but empty — a network error under follow mode, an opaqueredirect
      # under manual.
      def redirect_empty_location_py(url)
        ::Dommy::Resources::Response.new(
          status: 302, status_text: "", headers: {"Location" => ""},
          body: "", url: url.to_s, redirected: false
        )
      end

      # wptserve resources/clean-stash.py: take (clear) the stash for a token,
      # returning "1" if it held data, else "0".
      def clean_stash_py(uri, url)
        token = query(uri)["token"]
        body = @stash.delete(token) ? "1" : "0"
        ::Dommy::Resources::Response.new(
          status: 200, status_text: "OK", headers: {}, body: body, url: url.to_s, redirected: false
        )
      end

      # wptserve resources/preflight.py: a CORS endpoint that records a preflight
      # (OPTIONS) in the token stash and reflects it on the actual request via the
      # `x-did-preflight` header. On OPTIONS it echoes the allowed methods/headers
      # from the query (so the fetch layer's preflight check can pass/fail); on the
      # actual request it exposes the stashed preflight state.
      def preflight_py(method, uri, req_headers, url)
        q = query(uri)
        token = q["token"]
        acao = q["origin"] || "*"

        if method.to_s.upcase == "OPTIONS"
          req = (req_headers || {}).transform_keys { |k| k.to_s.downcase }
          headers = {"Content-Type" => "text/plain", "Access-Control-Allow-Origin" => acao}
          headers["Access-Control-Allow-Credentials"] = "true" if q.key?("credentials")
          headers["Access-Control-Max-Age"] = q["max_age"] if q["max_age"]
          headers["Access-Control-Allow-Headers"] = q["allow_headers"] if q["allow_headers"]
          headers["Access-Control-Allow-Methods"] = q["allow_methods"] if q["allow_methods"]
          @stash[token] = {
            "preflight" => "1",
            "control_request_headers" => req["access-control-request-headers"],
          } if token
          status = (q["preflight_status"] || "200").to_i
          return ::Dommy::Resources::Response.new(
            status: status, status_text: "OK", headers: headers, body: "", url: url.to_s, redirected: false
          )
        end

        req = (req_headers || {}).transform_keys { |k| k.to_s.downcase }
        data = (token && @stash.delete(token)) || {}
        headers = {
          "Content-Type" => "text/plain",
          "Access-Control-Allow-Origin" => acao,
          "Access-Control-Expose-Headers" =>
            "x-did-preflight, x-control-request-headers, x-referrer, x-preflight-referrer, x-origin",
          "x-did-preflight" => data["preflight"] || "0",
          "x-preflight-referrer" => data["preflight_referrer"].to_s,
          "x-referrer" => req["referer"].to_s,
          "x-origin" => req["origin"].to_s,
        }
        headers["Access-Control-Allow-Credentials"] = "true" if q.key?("credentials")
        headers["x-control-request-headers"] = data["control_request_headers"] if data["control_request_headers"]
        ::Dommy::Resources::Response.new(
          status: 200, status_text: "OK", headers: headers, body: "", url: url.to_s, redirected: false
        )
      end

      # wptserve resources/content.py: echo the request body back as the response
      # body (a `content=` query param overrides it), with a `content_type=`
      # (default text/plain) response type.
      def content_py(uri, body, url)
        q = query(uri)
        ::Dommy::Resources::Response.new(
          status: 200, status_text: "OK",
          headers: {"Content-Type" => (q["content_type"] || "text/plain")},
          body: q["content"] || body.to_s, url: url.to_s, redirected: false
        )
      end

      # wptserve resources/echo-content-type.py: return the request's Content-Type
      # header value as the response body (so a test can assert what was sent).
      def echo_content_type_py(req_headers, url)
        req = (req_headers || {}).transform_keys { |k| k.to_s.downcase }
        ::Dommy::Resources::Response.new(
          status: 200, status_text: "OK", headers: {"Content-Type" => "text/plain"},
          body: req["content-type"].to_s, url: url.to_s, redirected: false
        )
      end

      # First value per key, percent-decoded to raw bytes (ASCII-8BIT) so a
      # `content=` carrying non-UTF-8 response bytes survives intact.
      def query(uri)
        out = {}
        (uri.query || "").split("&").each do |pair|
          k, v = pair.split("=", 2)
          next if k.nil? || out.key?(k)

          out[k] = CGI.unescape(v.to_s)
        end
        out
      end
    end
  end
end
