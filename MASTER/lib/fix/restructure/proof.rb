# frozen_string_literal: true

require "set"

module Master
  module Fix
    class Restructure
      # What a restructure proves before it is kept. In every tree the files it
      # wrote still parse, and the tests that name what moved fail no more than
      # they did before. Each tree adds the check that shows its code still
      # loads: MasterProof, RailsProof, ScriptProof.
      class Proof
        TEST_CAP = 20
        TIMEOUT_S = 600

        def self.for(tree, repo_root)
          { "MASTER" => MasterProof, "RAILS" => RailsProof }.fetch(tree, ScriptProof).new(repo_root:, tree:)
        end

        def initialize(repo_root:, tree:)
          @repo_root = repo_root
          @tree_root = File.join(repo_root, tree)
        end

        # Measured on the tree before the plan is applied.
        SCORECARD_EXTENSIONS = %w[
          .rb .rake .js .mjs .css .scss .html .erb .yml .yaml .json .md .sh .zsh
        ].freeze

        def baseline(plan)
          tests = related_tests(plan)
          delete_needles = plan.deletes.to_h { |path| [path, names_in(path, nil)] }
          deleted_constants = plan.deletes.to_h { |path| [path, defined_constants(read(path))] }
          failing_before = failing(tests)
          {
            tests:, failing: failing_before, passing: tests - failing_before,
            tree: tree_baseline(plan), delete_needles:, deleted_constants:,
            scorecard: scorecard(extra_paths: plan.paths),
            contracts: contract_snapshot(extra_paths: plan.paths), ratchet: ratchet_snapshot
          }
        end

        # Machine-counted structural evidence. Semantic decision identity and
        # end-to-end traceability remain explicitly unmeasured until instrumented.
        def scorecard(extra_paths: [])
          out, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, "ls-files")
          raise "scorecard inventory failed: #{out.lines.last(2).join.strip}" unless status.success?

          prefix = "#{File.basename(@tree_root)}/"
          paths = (out.lines.map(&:strip).select { |path| path.start_with?(prefix) } + Array(extra_paths).map(&:to_s))
            .uniq.select do |path|
              File.file?(File.join(@repo_root, path)) &&
                SCORECARD_EXTENSIONS.include?(File.extname(path).downcase) &&
                !path.split("/").any? { |part| %w[node_modules vendor].include?(part) }
            end
          contents = paths.to_h { |path| [path, File.read(File.join(@repo_root, path), encoding: "UTF-8")] }
          children = Hash.new { |hash, key| hash[key] = Set.new }
          relative_paths = paths.map { |path| path.delete_prefix(prefix) }
          relative_paths.each do |path|
            parts = path.split("/")
            parts.each_index { |index| children[parts.take(index).join("/")] << parts[index] }
          end
          singleton_dirs = children.count do |parent, names|
            !parent.empty? && names.size == 1 &&
              parent.split("/").none? { |part| %w[test spec fixtures vendor node_modules].include?(part) }
          end
          definitions = contents.values.sum do |body|
            body.lines.count { |line| line.match?(/^\s*(?:class|module|def|function)\s+/) }
          end
          static_edges = contents.values.sum do |body|
            body.lines.count { |line| line.match?(/\b(?:require_relative|require|import)\b|\brender\s+["']/) }
          end
          {
            "files" => paths.size,
            "loc" => contents.values.sum { |body| body.lines.size },
            "concepts" => paths.size + definitions,
            "coupling_edges" => static_edges,
            "domain_depth" => relative_paths.map { |path| path.split("/").size }.max.to_i,
            "single_child_directories" => singleton_dirs,
            "unmeasured" => %w[cohesion decision_duplication traceability],
          }.freeze
        end

        # Snapshot caller-facing declarations and import/render statements so
        # compatibility changes are visible in the proof receipt.
        def contract_snapshot(extra_paths: [])
          out, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, "ls-files")
          raise "contract inventory failed: #{out.lines.last(2).join.strip}" unless status.success?

          prefix = "#{File.basename(@tree_root)}/"
          paths = (out.lines.map(&:strip).select { |path| path.start_with?(prefix) } + Array(extra_paths).map(&:to_s))
            .uniq.select do |path|
              File.file?(File.join(@repo_root, path)) &&
                %w[.rb .rake .js .mjs .erb .html].include?(File.extname(path).downcase) &&
                !path.split("/").any? { |part| %w[test spec fixtures].include?(part) }
            end
          constants = []
          references = []
          paths.each do |path|
            File.readlines(File.join(@repo_root, path), encoding: "UTF-8").each do |line|
              line.scan(/^\s*(?:class|module)\s+([A-Z][\w:]*)|^\s*([A-Z][\w]*)\s*=/).each do |pair|
                name = pair.compact.first
                constants << "#{path}:#{name}" if name
              end
              references << "#{path}:#{line.strip}" if line.match?(/\b(?:require_relative|require|import)\b|\brender\s+["']/)
            end
          end
          { "public_constants" => constants.uniq.sort, "require_paths" => references.uniq.sort }.freeze
        end

        def ratchet_snapshot
          path = File.join(@repo_root, "MASTER", "data", "spine.yml")
          return unless File.file?(path)

          body = File.read(path, encoding: "UTF-8")
          body[/^\s*core_recursive_files:\s*(\d+)\s*$/, 1]&.to_i
        end

        def test_evidence(before)
          after = @last_test_results
          {
            selected: before[:tests],
            passed_before: before.fetch(:passing, []),
            failing_before: before[:failing],
            passed_after: after&.fetch(:passing),
            failing_after: after&.fetch(:failing),
          }
        end

        # A reason the restructure fails, or nil.
        def failure(plan, before)
          syntax_failure(plan) || deletion_reference_failure(plan, before) ||
            unaliased_move_failure(plan, before) || tree_failure(plan, before[:tree]) || test_failure(before)
        end

        private

        def read(path) = File.file?(File.join(@repo_root, path)) ? File.read(File.join(@repo_root, path), encoding: "UTF-8") : nil

        def defined_constants(text)
          text.to_s.scan(/^\s*(?:class|module)\s+([A-Z][\w:]*)|^\s*([A-Z][\w]*)\s*=/).flatten.compact.uniq
        end

        # A deleted declaration reappearing under a new path is a move, not dead-code
        # removal. Keep a compatibility shim at the old path unless its non-public
        # status has been separately proved.
        def unaliased_move_failure(plan, before)
          plan.deletes.each do |path|
            old_constants = Array(before.fetch(:deleted_constants, {}).fetch(path, []))
            next if old_constants.empty?

            moved = plan.writes.reject { |target, _content| target == path }.filter_map do |target, content|
              shared = old_constants & defined_constants(content)
              [target, shared] unless shared.empty?
            end
            next if moved.empty?

            names = moved.flat_map(&:last).uniq
            destinations = moved.map(&:first)
            return "UNALIASED_MOVE: #{names.join(", ")} moves from #{path} to #{destinations.join(", ")}; retain a tested compatibility path or prove the old path is not public"
          end
          nil
        end

        def tree_baseline(_plan) = nil
        def tree_failure(_plan, _before) = nil

        def syntax_failure(plan)
          broken = plan.writes.keys.reject { |path| Syntax.valid?(File.join(@repo_root, path)) }
          "does not parse: #{broken.join(", ")}" unless broken.empty?
        end

        def deletion_reference_failure(plan, before)
          plan.deletes.filter_map do |path|
            next unless production_source?(path)

            needles = before.fetch(:delete_needles).fetch(path)
            hits = production_files(plan).filter_map do |file|
              lines = File.foreach(file).with_index(1).select do |text, _line|
                needles.any? { |needle| text.match?(needle) }
              end
              [file, lines] if lines.any?
            end
            next if hits.empty?

            "#{path} still has production references: #{references(hits).join("; ")}"
          end.first
        end

        # hits pairs each file with its matching [text, line] rows.
        def references(hits)
          hits.first(3).flat_map do |file, lines|
            lines.first(4).map { |text, line| "#{file}:#{line}: #{text.strip[0, 100]}" }
          end
        end

        def production_files(plan)
          out, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, "ls-files")
          return [] unless status.success?

          out.lines.map { |line| File.join(@repo_root, line.strip) }.select do |file|
            File.file?(file) && !plan.paths.include?(file.delete_prefix("#{@repo_root}/")) && !test_path?(file) &&
              %w[.rb .rake .js .mjs].include?(File.extname(file))
          end
        end

        def production_source?(path)
          path.end_with?(".rb", ".rake", ".js", ".mjs") && !test_path?(path)
        end

        def test_path?(path)
          path.to_s.split("/").any? { |part| %w[test spec fixtures].include?(part) }
        end

        def test_failure(before)
          failing_after = failing(before[:tests])
          @last_test_results = {
            failing: failing_after,
            passing: before[:tests] - failing_after,
          }
          added = failing_after - before[:failing]
          "tests now failing: #{added.join(", ")}" unless added.empty?
        end

        def failing(tests) = tests.reject { |test| run_test(test).last.success? }

        # Test files, relative to the tree, that name a moved file's stem or a
        # constant it defines, most mentions first.
        def related_tests(plan)
          needles = needles_for(plan)
          return [] if needles.empty?

          hits = test_files(plan).to_h { |file| [file, needles.count { |needle| File.read(file).include?(needle) }] }
          hits.select { |_file, count| count.positive? }.sort_by { |_file, count| -count }
              .first(TEST_CAP).map { |file, _count| file.delete_prefix("#{@tree_root}/") }
        end

        def needles_for(plan) = plan.paths.flat_map { |path| names_in(path, plan.writes[path]) }.uniq

        def names_in(path, new_text)
          stem = File.basename(path, ".*")
          old = File.join(@repo_root, path)
          text = [new_text, File.file?(old) ? File.read(old) : nil].compact.join("\n")
          constants = text.scan(/^\s*(?:class|module)\s+([A-Z]\w+)/).flatten - Restructure.namespaces(@tree_root)
          [stem.length >= 4 ? stem : nil, *constants].compact
        end
      end
    end
  end
end
