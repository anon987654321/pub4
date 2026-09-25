# frozen_string_literal: true

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
        def baseline(plan)
          tests = related_tests(plan)
          delete_needles = plan.deletes.to_h { |path| [path, names_in(path, nil)] }
          { tests:, failing: failing(tests), tree: tree_baseline(plan), delete_needles: }
        end

        # A reason the restructure fails, or nil.
        def failure(plan, before)
          syntax_failure(plan) || deletion_reference_failure(plan) || tree_failure(plan, before[:tree]) || test_failure(before)
        end

        private

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

            refs = hits.first(3).flat_map do |file, lines|
              lines.first(4).map { |line, text| "#{file}:#{line}: #{text.strip[0, 100]}" }
            end
            "#{path} still has production references: #{refs.join("; ")}"
          end.first
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
          added = failing(before[:tests]) - before[:failing]
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
