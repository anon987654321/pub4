# frozen_string_literal: true

module Master
  module Review
    module Scan
      stale_config = (Master.load_yaml(Master.data_path("rules.yml")) || {})["stale_namespaces"] || {}
      stale_constants = Array(stale_config["stale_constants"]).filter_map { |row| row["old"] if row.is_a?(Hash) }
      # A retired name counts only as a whole constant path. `\b` sits between a
      # letter and a colon, so /\bMaster::CLI\b/ matched inside every legitimate
      # Master::CLI::* reference — 25 of selfcheck's 71 findings, all false.
      stale_pattern = Regexp.union(
        stale_constants.map { |name| /(?<![\w:])#{Regexp.escape(name)}(?!::|\w)/ }
      )

      RuleDSL.rule :STALE_NAMESPACE,
        severity: :error,
        tags: %i[ONE_SOURCE],
        applies_to: %i[ruby],
        description: "retired constants must not return" do |source, path:|
          # This file names the retired constants, so it flags itself. The old
          # exemption named stale_namespace_rule.rb, which no longer exists.
          next [] if stale_constants.empty? || path.end_with?("naming_rules.rb")

          scan_lines(source, stale_pattern, message: "retired constant — use data/rules.yml#stale_namespaces replacement")
        end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        RuleDSL.rule :PARAMETERIZED_SLUG,
          severity: :warning,
          tags: %i[FLAT_HIERARCHY DRY],
          applies_to: %i[ruby],
          autofix: false,
          description: "path is dense Rails-parameterize slug — Strunk-clean snake_case" do |_src, path:|
          rel = path.to_s
          # A migration's filename is its schema_migrations key, and Rails finds
          # application_* by name. Neither can be renamed on naming-density
          # grounds, and 58 of brgen's 71 findings were migrations.
          next [] if rel.match?(%r{/(test|spec|node_modules|db/migrate)/|/application_\w+\.rb\z})

          Master::Ground::ParameterizedSlug.path_issues(rel).map do |issue|
            target = issue.to == issue.from ? issue.to : "#{File.dirname(rel)}/#{issue.to}.rb".gsub(%r{\./}, "")
            message = case issue.action
                      when "merge" then "Flat Hierarchy — #{issue.reason} (#{target})"
                      else "Flat Hierarchy — #{issue.reason}#{" → #{target}" if issue.to != issue.from}"
                      end
            finding(line: 1, message:)
          end
        end
      end
    end
  end
end

# TYPE_IN_NAME and NUMBERED_NAME, the two naming detectors from TODO.md's
# AST-detector backlog. AST rather than a Law line-regex because both are about
# declarations — a method, a parameter, a local, an ivar — and a regex over raw
# lines cannot tell a declaration from a mention of one in a comment.
module Master
  module Review
    module Scan
      module Rules
        # A name that says what type it is says the one thing the code already
        # says. `text_str` is a String either way; the name's job was to say
        # which text.
        #
        # Three exclusions, each from a measured false positive rather than a
        # guess. `to_hash` / `from_hash` are the Ruby conversion protocol and
        # renaming them breaks it. A digest is also spelled `_hash`, and
        # `prev_hash` renamed to `prev` loses the only thing the name said. And
        # `_list` is a domain noun as often as a type: an allow_list is not an
        # Array pretending to be named, and old_string is the edit-tool schema
        # this runtime hands a model. 85 findings before those exclusions, 44 after.
        class TypeInNameRule < Rule
          SUFFIX = /_(?:string|str|array|hash|object|list)\z/
          CONVERSION = /\A(?:to|from|as|into)_/
          DIGEST = /(?:prev|last|stable|content|commit|file|source|body|digest|checksum|chain|enacted)_hash\z/
          # old_string / new_string are the edit-tool schema this runtime
          # exposes to a model, so they are an external contract like to_hash.
          KEEP = %w[
            allow_list block_list deny_list mailing_list free_list watch_list
            skip_list word_list wait_list short_list packing_list price_list
            play_list guest_list old_string new_string old_str new_str
          ].freeze

          def initialize
            super()
            @id = "TYPE_IN_NAME"
            @description = "a name that encodes its own type says nothing the code did not"
            @severity = :info
            @rule_tags = %i[DOMAIN_LANGUAGE LOAD_BEARING_NAMES]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            named(ast).filter_map do |line, kind, name|
              next unless flagged?(name)

              finding(line:, message: "#{kind} #{name} encodes its type — name it for what it holds")
            end.uniq
          end

          private

          def named(ast)
            rows = []
            each_node(ast, Prism::DefNode).each do |def_node|
              rows << [def_node.location.start_line, "method", def_node.name.to_s]
              parameter_names(def_node).each { |name| rows << [def_node.location.start_line, "parameter", name] }
            end
            each_node(ast, Prism::LocalVariableWriteNode).each do |node|
              rows << [node.location.start_line, "local", node.name.to_s]
            end
            each_node(ast, Prism::InstanceVariableWriteNode).each do |node|
              rows << [node.location.start_line, "ivar", node.name.to_s.delete_prefix("@")]
            end
            rows
          end

          def flagged?(name)
            name.match?(SUFFIX) && !name.match?(CONVERSION) && !name.match?(DIGEST) && !KEEP.include?(name)
          end
        end

        # A bare sequence number in a name, where a sibling in the same file
        # carries the same stem and a different one: mix_v7 beside mix_v11. The
        # number says there was another one and nothing about the difference.
        #
        # The sibling requirement is what makes this measurable rather than
        # noisy, and it was added after measuring. Without it: 15 findings, of
        # which fet1176, fairchild670 and stc8 are the names of real hardware —
        # an 1176 compressor, a Fairchild 670, a Coles STC-8 — and inv3 and
        # normalize_to_y1 are maths. A lone number in a name is usually a fact
        # about the world. Locals were measured and dropped for the same reason:
        # 114 findings, nearly all of them dilla and postpro, where t1 and d8 are
        # the notation the DSP is transcribed from.
        class NumberedNameRule < Rule
          NUMBERED = /\A(.*?)(?:_v)?(\d+)\z/
          KEEP = /
            (?:sha|md|crc|base|utf|latin|iso|rfc|x|ipv|http|oauth|ec|s3|p|h|mp|
               aes|rsa|ed|argon|bcrypt|blake|id|ansi|cp|win|css|es|vips|gl|webgl|
               float|int|uint|bit|px|rem|em|ms|hz|db|k|fp|bf|q|load|capture)\d+\z
          /x

          def initialize
            super()
            @id = "NUMBERED_NAME"
            @description = "numbered siblings name no difference between themselves"
            @severity = :info
            @rule_tags = %i[DOMAIN_LANGUAGE LOAD_BEARING_NAMES]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            numbered = stems(ast)
            by_stem = numbered.group_by { |stem, _name, _line| stem }

            numbered.filter_map do |stem, name, line|
              siblings = by_stem[stem].map { |_stem, sibling, _line| sibling }.uniq - [name]
              next if siblings.empty?

              finding(line:, message: "#{name} sits beside #{siblings.join(", ")} — the number names no difference")
            end
          end

          private

          def stems(ast)
            names = each_node(ast, Prism::DefNode).map { |node| [node.name.to_s, node.location.start_line] }
            names += each_node(ast, Prism::ClassNode).map { |node| [snake(node.name.to_s), node.location.start_line] }

            names.filter_map do |name, line|
              next if name.match?(KEEP)

              match = NUMBERED.match(name)
              next if match.nil? || match[1].empty?

              [match[1], name, line]
            end
          end

          def snake(name)
            name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
          end
        end
      end
    end
  end
end
