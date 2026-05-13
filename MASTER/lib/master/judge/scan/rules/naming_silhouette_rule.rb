# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Predicates end `?`, mutators end `!`, factories start `build_`/`make_`,
      # finders start `find_`. Methods that lie about their shape are POLA bombs.
      class NamingSilhouetteRule < Rule
        BOOL_RETURN = /(?:return\s+(?:true|false)\b|\A\s*(?:true|false)\s*\z|\.(?:nil|empty|present|blank|valid|include|any|all|none|one|exist|persisted|new_record)\?\s*\z)/.freeze
        FACTORY_PREFIX = /\Abuild_|\Amake_|\Acreate_/.freeze
        FINDER_PREFIX  = /\Afind_/.freeze

        def initialize
          super
          @id          = "naming_silhouette"
          @description = "Method name doesn't match its return shape — predicate/mutator/factory drift"
          @severity    = :warning
          @rule_tags  = %i[POLA_PRINCIPLE SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          methods(code).each do |name, line, body|
            findings << finding(line: line, message: "predicate `#{name}` should end with `?`") if predicate_unmarked?(
name, body)
            findings << finding(line: line, 
message: "mutator `#{name}` ends with `!` but body has no mutation") if bang_without_mutation?(
name, body)
            findings << finding(line: line, 
message: "factory `#{name}` should return a built object, not nil") if factory_returns_nil?(
name, body)
          end
          findings
        end

        private

        def methods(code)
          lines = code.lines
          out = []
          lines.each_with_index do |line, i|
            next unless line =~ /\A\s*def\s+(self\.)?([A-Za-z_][A-Za-z0-9_!?=]*)/
            name = Regexp.last_match(2)
            body = capture_body(lines, i)
            out << [name, i + 1, body]
          end
          out
        end

        def capture_body(lines, start)
          depth = 0
          buf = []
          lines[start..].each_with_index do |l, j|
            depth += 1 if l =~ /\A\s*(?:def|do\b|if|unless|case|while|until|begin|class|module)\b/ && j > 0
            depth += 1 if j.zero?
            depth -= 1 if l =~ /\A\s*end\b/
            buf << l
            return buf.join if depth.zero?
          end
          buf.join
        end

        def predicate_unmarked?(name, body)
          return false if name.end_with?("?", "!", "=")
          body.match?(BOOL_RETURN)
        end

        def bang_without_mutation?(name, body)
          return false unless name.end_with?("!")
          !body.match?(/[@\w]+\s*=|\.\w+!\b|<<|push|delete|clear|update|save|destroy|create|merge!/)
        end

        def factory_returns_nil?(name, body)
          return false unless name.match?(FACTORY_PREFIX)
          body.match?(/\Areturn\s+nil\b|\.\.\.\s*nil\s*\z/)
        end
      end
    end
  end
  end
end
