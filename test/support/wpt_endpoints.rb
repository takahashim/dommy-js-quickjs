# frozen_string_literal: true

require "cgi"
require "uri"

module Dommy
  module Js
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
      def get(url, headers: {}) = request(method: "GET", url: url, headers: headers)

      def request(method:, url:, headers: {}, body: nil)
        uri = parse(url)
        return nil unless uri

        case ::File.basename(uri.path)
        when "status.py" then status_py(uri, url)
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
