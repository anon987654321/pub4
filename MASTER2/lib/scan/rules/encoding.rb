# frozen_string_literal: true

module MASTER
  module Scan
    module Rules
      # Encoding -- detects and auto-fixes non-ASCII Unicode chars and CRLF line endings.
      # Both issues cause crashes on OpenBSD when locale is not UTF-8.
      module Encoding
        include Scan::Rule

        UNICODE_MAP = {
          "\u2014" => "--",  # em dash
          "\u2013" => "-",   # en dash
          "\u2018" => "'",   # left single quote
          "\u2019" => "'",   # right single quote
          "\u201c" => '"',   # left double quote
          "\u201d" => '"',   # right double quote
          "\u2026" => "...", # ellipsis
          "\u00b7" => "*",   # middle dot
          "\u00a0" => " ",   # non-breaking space
          "\u200b" => "",    # zero-width space
          "\u2022" => "*",   # bullet
          "\u2192" => "->",  # right arrow
          "\u2190" => "<-",  # left arrow
          "\u25b8" => ">",   # right-pointing triangle
          "\u203a" => ">",   # single right guillemet
          "\u2039" => "<",   # single left guillemet
        }.freeze

        UNICODE_RE = Regexp.union(UNICODE_MAP.keys).freeze

        def self.check(code, path: nil)
          findings = []

          if code.include?("\r\n") || code.include?("\r")
            findings << {
              rule:      :crlf,
              message:   "CRLF line endings -- run Scan::Rules::Encoding.fix",
              line:      1,
              severity:  :minor,
              autofix:   true,
              principle: nil,
            }
          end

          code.each_line.with_index(1) do |line, num|
            next unless line.match?(UNICODE_RE)

            findings << {
              rule:      :unicode,
              message:   "Non-ASCII Unicode chars -- run Scan::Rules::Encoding.fix",
              line:      num,
              severity:  :minor,
              autofix:   true,
              principle: nil,
            }
          end

          findings
        end

        # Pure-Ruby fix: normalize line endings then map Unicode to ASCII.
        def self.fix(content)
          content = content.gsub("\r\n", "\n").gsub("\r", "\n")
          content.gsub(UNICODE_RE) { |m| UNICODE_MAP.fetch(m, m) }
        end
      end
    end
  end
end
