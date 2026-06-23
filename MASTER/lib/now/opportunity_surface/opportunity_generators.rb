# frozen_string_literal: true

require "open3"
require "prism"

module Master
  module Now
    class OpportunitySurface
      module OpportunityGenerators
        private

        def pattern_extraction_opportunities
          return [] unless @scanner

          rule = @scanner.rules.find { |candidate| candidate.id.to_s == "PATTERN_EXTRACTION" }
          return [] unless rule

          lib_files.first(20).filter_map do |path|
            result = @scanner.scan(path, rules: [rule])
            next unless result.ok?

            result.value!.filter_map do |finding|
              next if finding[:message].to_s.empty?

              prop(
                action: "/refactor",
                reason: pattern_extraction_reason(path, finding[:message]),
                weight: 0.7
              )
            end
          end.flatten.first(3)
        rescue StandardError
          []
        end

        def semantic_duplicate_opportunities
          lib_files.first(20).filter_map do |path|
            source = File.read(path, encoding: "UTF-8")
            methods = method_bodies_from_source(source)
            next if methods.size < 2

            pair = best_duplicate_pair(methods)
            next unless pair && pair[:similarity] >= 0.8

            rel = path.delete_prefix("#{@root}/")
            prop(
              action: "/refactor",
              reason: "#{rel} has near-duplicate methods `#{pair[:a][:name]}` and `#{pair[:b][:name]}` (#{format('%.2f', pair[:similarity])}); extract the shared core",
              weight: 0.73
            )
          rescue StandardError
            nil
          end.compact.first(3)
        end

        def literal_abstraction_opportunities
          literals = Hash.new { |hash, key| hash[key] = [] }
          lib_files.first(40).each do |path|
            source = File.read(path, encoding: "UTF-8")
            source.scan(/["']([^"']{5,60})["']/).each do |match|
              literal = match.first.to_s.strip
              next unless literal.match?(/\A[a-zA-Z0-9 _\-:.,\/]+\z/)
              next if literal.match?(/\A(?:https?:|\/|\.\/|#[0-9a-fA-F]{3,6})/)

              literals[literal] |= [path]
            end
          rescue StandardError
            next
          end

          literals.filter_map do |literal, files|
            next unless files.size >= 3

            rel_files = files.first(3).map { |path| path.delete_prefix("#{@root}/") }
            prop(
              action: "/refactor",
              reason: "literal `#{literal}` appears in #{files.size} files (#{rel_files.join(', ')}); extract a named constant or value object",
              weight: 0.63
            )
          end.first(3)
        end

        def sibling_fix_opportunities
          return [] unless @scanner
          return [] unless @bus&.respond_to?(:tail)

          event = @bus.tail(50).reverse.find { |entry| entry[:event].to_s == "rule_loop:fix_applied" }
          return [] unless event

          payload = event[:payload] || {}
          path = payload[:file].to_s
          rule_id = payload[:rule].to_s
          return [] if path.empty? || rule_id.empty?

          rule = find_rule(rule_id)
          return [] unless rule

          siblings = sibling_paths(path)
          siblings.filter_map do |sibling|
            next unless File.file?(sibling)
            result = @scanner.scan(sibling, rules: [rule])
            next unless result.ok?
            next if result.value!.empty?

            rel = sibling.delete_prefix("#{@root}/")
            prop(
              action: "/fix",
              reason: "#{rel} still carries #{rule_id}; extend the same fix to the sibling file",
              weight: 0.71
            )
          end.first(3)
        rescue StandardError
          []
        end

        def layer_purity_opportunities
          offenders = Dir.glob(File.join(@root, "MASTER", "lib", "now", "**", "*.rb")).filter_map do |path|
            src = File.read(path, encoding: "UTF-8")
            next unless src.match?(/require_relative\s+["']\.\.\/judge/)
            next unless src.match?(/Master::Judge::/)

            path.delete_prefix("#{@root}/")
          rescue StandardError
            nil
          end
          return [] if offenders.empty?

          [prop(
            action: "/review",
            reason: "lib/now reaches directly into judge internals in #{offenders.first(3).join(', ')}; route through Pipeline instead",
            weight: 0.78
          )]
        end

        def test_gap_opportunities
          lib_files = Dir.glob(File.join(@root, "MASTER", "lib", "**", "*.rb")).select { |path| File.file?(path) }
          test_files = Dir.glob(File.join(@root, "MASTER", "test", "test_*.rb")).select { |path| File.file?(path) }
          test_basenames = test_files.map { |path| File.basename(path) }

          lib_files.filter_map do |path|
            rel = path.delete_prefix("#{@root}/")
            expected = "test_#{File.basename(path, ".rb")}.rb"
            next if test_basenames.include?(expected)

            prop(
              action: "/review",
              reason: "#{rel} has no test counterpart; add coverage with an estimated small effort",
              weight: 0.58
            )
          end.first(5)
        end

        def commit_review_opportunities
          head, stat = recent_commit_review
          return [] unless head && stat.any?

          rows = stat.filter_map do |path, lines|
            next unless lines >= REVIEW_LINES_THRESHOLD

            prop(
              action: "/review",
              reason: "#{path} changed #{lines} lines in #{head}; review the hot file",
              weight: 0.8
            )
          end.first(5)
          if stat.size > 3
            rows << prop(
              action: "/scan",
              reason: "simpler alternative: split #{head} into two passes instead of reviewing the whole change at once",
              weight: 0.48
            )
          end
          rows
        end

        def recent_commit_review
          out, _, status = Open3.capture3("git", "-C", @root, "show", "--stat", "--numstat", "--format=%h", "HEAD")
          return [nil, {}] unless status.success?

          lines = out.lines.map(&:strip)
          head = lines.shift
          stat = {}
          lines.each do |line|
            next unless line.match?(/\A\d+\t\d+\t/)

            adds, dels, path = line.split(/\t/, 3)
            stat[path] = adds.to_i + dels.to_i
          end
          [head, stat]
        rescue StandardError
          [nil, {}]
        end

        def sibling_paths(path)
          dir = File.dirname(path)
          ext = File.extname(path)
          Dir.glob(File.join(dir, "*#{ext}")).reject { |candidate| candidate == path }
        end

        def find_rule(rule_id)
          return nil unless @scanner.respond_to?(:rules)

          @scanner.rules.find { |rule| rule.id.to_s.casecmp?(rule_id.to_s) }
        end

        def lib_files
          Dir.glob(File.join(@root, "MASTER", "lib", "**", "*.rb")).select { |path| File.file?(path) }
        end

        def method_bodies_from_source(source)
          tree = Prism.parse(source)
          return [] if tree.failure?

          bodies = []
          visit_prism(tree.value) do |node|
            next unless node.is_a?(Prism::DefNode)
            lines = source.lines[(node.location.start_line - 1)...node.location.end_line]
            next if lines.nil? || lines.empty?

            bodies << {
              name: node.name.to_s,
              line: node.location.start_line,
              tokens: normalized_tokens(lines.join),
            }
          end
          bodies
        rescue StandardError
          []
        end

        def visit_prism(node, &block)
          return unless node.respond_to?(:child_nodes)
          block.call(node)
          node.child_nodes.compact.each { |child| visit_prism(child, &block) }
        end

        def normalized_tokens(source)
          source.downcase
                .gsub(/#.*$/, " ")
                .gsub(/"(?:\\.|[^"])*"|'(?:\\.|[^'])*'/, " STRING ")
                .gsub(/\b\d+(?:\.\d+)?\b/, " NUM ")
                .scan(/[a-z_][a-z0-9_]*/)
                .reject { |token| token.size < 3 || %w[def end if then else elsif do nil true false self class module].include?(token) }
        end

        def best_duplicate_pair(methods)
          best = nil
          methods.combination(2).each do |a, b|
            score = cosine_similarity(a[:tokens], b[:tokens])
            next if best && score <= best[:similarity]

            best = { a: a, b: b, similarity: score }
          end
          best
        end

        def cosine_similarity(a_tokens, b_tokens)
          return 0.0 if a_tokens.empty? || b_tokens.empty?

          a = a_tokens.tally
          b = b_tokens.tally
          common = a.keys & b.keys
          dot = common.sum { |token| a[token] * b[token] }
          mag_a = Math.sqrt(a.values.sum { |n| n * n })
          mag_b = Math.sqrt(b.values.sum { |n| n * n })
          return 0.0 if mag_a.zero? || mag_b.zero?

          dot / (mag_a * mag_b)
        end
      end
    end
  end
end
