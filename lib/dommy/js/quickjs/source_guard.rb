# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Source-level workaround for a QuickJS bytecode-generation bug: a `for...of`
      # whose ITERABLE expression contains a `yield` fails to COMPILE with an
      # internal "stack underflow" error (the for-of iterator-close finally region
      # miscomputes the operand stack across the generator suspend). V8 / real
      # browsers compile it fine, so SPA bundles ship it — e.g. note.com's modern
      # build has `for (var f of (yield O(), _)) v(f)`, and the whole code-split
      # chunk fails to load, so the app never mounts.
      #
      # The fix hoists the iterable into a temp `var` so the `yield` leaves the
      # for-of operand position — `for (x of (yield a, b)) …` becomes
      # `var t = (yield a, b); for (x of t) …` — semantically identical, and it
      # compiles. Applied ONLY as a retry after a genuine "stack underflow" compile
      # failure (see Backend), so working scripts are never rewritten and an
      # imperfect transform cannot regress anything (the source already failed).
      module SourceGuard
        module_function

        # The marker QuickJS raises for this codegen bug.
        ERROR_MARKER = "stack underflow"

        def relevant_error?(error)
          error.respond_to?(:message) && error.message.to_s.include?(ERROR_MARKER)
        end

        # Rewrite every `for...of` whose iterable contains a `yield`, hoisting the
        # iterable into a preceding `var`. Returns the source unchanged when there
        # is nothing to do.
        def fix_for_of_yield(source)
          return source unless source.include?("yield")

          # Scan at the BYTE level (binary encoding): on a multibyte (UTF-8) source
          # — note's bundle has Japanese strings — Ruby's character indexing is
          # O(index), making a char-by-char pass O(n^2). All tokens we look for are
          # ASCII, and UTF-8 continuation bytes (>= 0x80) never collide with them,
          # so byte scanning is both safe and O(1) per position.
          Rewriter.new(source.b).run.force_encoding(source.encoding)
        end

        IDENT = /[A-Za-z0-9_$]/.freeze

        def ident_char?(ch)
          !ch.nil? && IDENT.match?(ch)
        end

        # A `/` begins a regex (not division) unless the previous significant code
        # char can end an expression (ident / `)` / `]` / a literal).
        def regex_allowed?(prev_sig)
          return true if prev_sig.nil?
          return false if ident_char?(prev_sig)

          !")]'\"`".include?(prev_sig)
        end

        # If `src[i]` begins a string, template, regex literal, or comment, return
        # the index just after it; otherwise nil. `prev_sig` (previous significant
        # code char) disambiguates a regex `/` from division.
        def atom_end(src, i, prev_sig)
          case src[i]
          when "/"
            if src[i + 1] == "/"
              src.index("\n", i) || src.length
            elsif src[i + 1] == "*"
              (idx = src.index("*/", i + 2)) ? idx + 2 : src.length
            elsif regex_allowed?(prev_sig)
              scan_regex(src, i)
            end
          when "'", '"'
            scan_quote(src, i, src[i])
          when "`"
            scan_template(src, i)
          end
        end

        def scan_quote(src, i, quote)
          j = i + 1
          n = src.length
          while j < n
            c = src[j]
            return j + 1 if c == quote

            j += c == "\\" ? 2 : 1
          end
          n
        end

        def scan_template(src, i)
          j = i + 1
          n = src.length
          while j < n
            c = src[j]
            return j + 1 if c == "`"
            if c == "\\"
              j += 2
              next
            end
            if c == "$" && src[j + 1] == "{"
              close = match_bracket(src, j + 1)
              return n unless close

              j = close + 1
              next
            end
            j += 1
          end
          n
        end

        # End of a regex literal at `i` (past its flags), or nil if it isn't one
        # (an unescaped newline before the closing `/` → it was division).
        def scan_regex(src, i)
          j = i + 1
          n = src.length
          in_class = false
          while j < n
            c = src[j]
            case c
            when "\\" then j += 2; next
            when "[" then in_class = true
            when "]" then in_class = false
            when "/"
              unless in_class
                j += 1
                j += 1 while j < n && src[j] =~ /[a-z]/i
                return j
              end
            when "\n"
              return nil
            end
            j += 1
          end
          nil
        end

        # Index of the close bracket matching the (/[/{ at `open`, skipping nested
        # brackets, strings, templates, regexes and comments. `limit` bounds the
        # scan (a for-head is short; bounding keeps the whole pass linear and
        # avoids a runaway scan when a mis-lexed token unbalances brackets).
        def match_bracket(src, open, limit: nil)
          pairs = {"(" => ")", "[" => "]", "{" => "}"}
          want = [pairs[src[open]]]
          i = open + 1
          n = src.length
          n = [n, open + limit].min if limit
          prev = src[open]
          while i < n
            stop = atom_end(src, i, prev)
            if stop
              prev = src[stop - 1]
              i = stop
              next
            end
            c = src[i]
            if pairs.key?(c)
              want << pairs[c]
            elsif ")]}".include?(c)
              return i if want.size == 1 && want.last == c

              want.pop if want.last == c
            end
            prev = c unless c =~ /\s/
            i += 1
          end
          nil
        end

        # Position of the for-of `of` keyword at the top level of a for-head, or nil
        # for a for-in / C-style for (a top-level `;` rules out for-of).
        def top_level_of(head)
          depth = 0
          i = 0
          n = head.length
          prev = nil
          while i < n
            stop = atom_end(head, i, prev)
            if stop
              prev = head[stop - 1]
              i = stop
              next
            end
            c = head[i]
            case c
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth -= 1
            when ";" then return nil if depth.zero?
            when "o"
              if depth.zero? && head[i, 2] == "of" &&
                 !ident_char?(i.zero? ? nil : head[i - 1]) && !ident_char?(head[i + 2])
                return i
              end
            end
            prev = c unless c =~ /\s/
            i += 1
          end
          nil
        end

        def contains_yield?(expr)
          i = 0
          n = expr.length
          prev = nil
          while i < n
            stop = atom_end(expr, i, prev)
            if stop
              prev = expr[stop - 1]
              i = stop
              next
            end
            if expr[i] == "y" && expr[i, 5] == "yield" &&
               !ident_char?(i.zero? ? nil : expr[i - 1]) && !ident_char?(expr[i + 5])
              return true
            end
            prev = expr[i] unless expr[i] =~ /\s/
            i += 1
          end
          false
        end

        # Walks source once, copying literals/comments verbatim and rewriting a
        # for-of-with-yield-in-iterable found at a statement boundary.
        class Rewriter
          # Upper bound on a `for (...)` head length we will consider (well above
          # any real for-of header, including a large iterable expression).
          HEAD_SCAN_LIMIT = 64 * 1024

          def initialize(src)
            @src = src
            @n = src.length
          end

          def run
            out = +""
            i = 0
            prev = nil  # previous significant code char
            counter = 0
            while i < @n
              stop = SourceGuard.atom_end(@src, i, prev)
              if stop
                out << @src[i...stop]
                prev = @src[stop - 1]
                i = stop
                next
              end

              ch = @src[i]
              if ch == "f" && @src[i, 3] == "for" &&
                 !SourceGuard.ident_char?(i.zero? ? nil : @src[i - 1]) &&
                 !SourceGuard.ident_char?(@src[i + 3]) &&
                 boundary?(prev)
                rewrite = transform_for(i, counter)
                if rewrite
                  out << rewrite[:text]
                  i = rewrite[:next]
                  counter += 1
                  prev = ")"
                  next
                end
              end

              out << ch
              prev = ch unless ch =~ /\s/
              i += 1
            end
            out
          end

          private

          # A `var t = …;` may be inserted before `for` only at a statement
          # boundary; otherwise (e.g. `if (c) for (…)`) it would change meaning.
          def boundary?(prev_sig)
            prev_sig.nil? || ";{}".include?(prev_sig)
          end

          def transform_for(for_idx, counter)
            open = for_idx + 3
            open += 1 while open < @n && @src[open] =~ /\s/
            return nil unless @src[open] == "("

            # A for-head is short; cap the scan so an unbalanced (mis-lexed) head
            # can't turn the per-`for` work into an O(n) scan.
            close = SourceGuard.match_bracket(@src, open, limit: HEAD_SCAN_LIMIT)
            return nil unless close

            head = @src[(open + 1)...close]
            of_at = SourceGuard.top_level_of(head)
            return nil unless of_at

            decl = head[0...of_at]
            iterable = head[(of_at + 2)..].to_s
            return nil unless SourceGuard.contains_yield?(iterable)

            tmp = "__dommyForOf#{counter}"
            {text: "var #{tmp}=(#{iterable});for(#{decl}of #{tmp})", next: close + 1}
          end
        end
      end
    end
  end
end
