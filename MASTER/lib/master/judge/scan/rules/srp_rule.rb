# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # SrpRule — Single Responsibility Principle.
      # A class should have one reason to change. Flags classes whose public methods
      # span multiple concern domains (persistence, rendering, validation, networking, parsing).
      class SrpRule < Rule
        CONCERNS = {
          persistence: /\b(save|load|read_\w|write_\w|persist|store_\w|fetch_\w|find_by|delete|destroy|insert|upsert)\b/,
          rendering:   /\b(render|display|format_\w|present|to_html|draw|paint|emit|output_\w)\b/,
          validation:  /\b(valid\?|validate[^d]|check_\w|verify_\w|assert_\w|ensure_\w|guard_\w)\b/,
          networking:  /\b(request_\w|http_\w|send_request|receive_\w|connect_\w|socket_\w)\b/,
          parsing:     /\b(parse_\w|tokenize|lex_\w|extract_\w|decode_\w|encode_\w|deserialize|serialize)\b/,
        }.freeze

        def initialize
          super
          @id          = "srp"
          @description = "Single Responsibility Principle — class spans multiple concern domains"
          @severity    = :warning
          @rule_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          public_methods = code.scan(/^\s{2,8}def\s+(\w+)/).flatten
          return [] if public_methods.size < 4

          concerns_found = CONCERNS.select { |_, pat| public_methods.any? { |m| m.match?(pat) } }
          return [] if concerns_found.size < 2

          class_name = code.match(/class\s+(\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} spans #{concerns_found.size} domains " \
                     "(#{concerns_found.keys.join(", ")}) — split by single responsibility (SRP)"
          )]
        end
      end
    end
  end
  end
end
