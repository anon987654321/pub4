# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
      # Detects methods/classes/modules present in recent git history but absent now.
      # Wraps CommitGuard as a standard scan Rule so it runs in the scanner pipeline.
        class AstOmissionRule < Rule
          def self.auto_build? = false

          def initialize(root: Dir.pwd, depth: CommitGuard::DEFAULT_DEPTH)
            super()
            @id = "ast_omission"; @description = "symbol dropped vs recent commits"
            @severity = :warning; @rule_tags = %i[COMPLETENESS]; @auto_fix = false
            @root = File.expand_path(root)
            @guard = CommitGuard.new(root: @root, depth:)
          end

          def check(_code, path:)
            return [] unless path.to_s.end_with?(".rb")

            rel = relativize(path)
            return [] unless rel

            omissions = @guard.check(paths: [rel])
            omissions.map { |o| finding(line: 1, message: "#{o.type} #{o.name} dropped (last seen #{o.last_seen_at})") }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "ast_omission_rule.check", event_bus: nil)
            []
          end

          private

          def relativize(path)
            full = File.expand_path(path)
            prefix = @root + File::SEPARATOR
            full.start_with?(prefix) ? full.delete_prefix(prefix) : File.basename(full)
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        # Every Rule subclass must have a matching test file; gaps mean untested enforcement.
        class RuleCoverageRule < Rule
          def self.auto_build? = false

          def initialize(root:)
            super()
            @id = "rule_coverage"
            @description = "Rule subclass has no corresponding test file"
            @severity = :warning
            @auto_fix = false
            @rule_tags = %i[TEST_COVERAGE]
            @root = root
            @test_dir = File.join(root, "test")
          end

          # Asks the question the description asks — has this Rule subclass a
          # test — rather than whether a file is named after it.
          #
          # It used to require the path end `_rule.rb` and look for
          # `<base>_test.rb`. One file in sixteen ends `_rule.rb`; the rest are
          # `*_rules.rb` and hold nearly every rule there is. And MASTER names
          # tests `test_<base>.rb`, 283 files to 1, so the glob described a
          # convention this tree does not use. Over all sixteen files it
          # produced one finding, and `test/test_law_bridge_rule.rb` existed.
          # Fifteen skipped, one false positive, nothing correct.
          #
          # Coverage is a mention anywhere in test/, of the class or of its id,
          # because the tests that exercise these rules mostly do it in bulk —
          # test_smell_detectors.rb and test_scan_rule_false_positives.rb reach
          # rules by id through the scanner. Requiring a file per class would
          # report those as uncovered, which is the false-positive machine the
          # old shape already was, pointed the other way.
          def check(code, path:)
            return [] unless path.include?("/review/scan/rules/") && path.end_with?(".rb")

            subclasses(code).reject { |name, id| covered?(name, id) }
              .map { |name, _| finding(line: 1, message: "rule_coverage: no test names #{name}") }
          end

          private

          def subclasses(code)
            code.enum_for(:scan, /^\s*class (\w+Rule) < Rule\b/).map do
              name = Regexp.last_match(1)
              [name, code[Regexp.last_match.end(0), 2000][/@id\s*=\s*["']([\w.]+)["']/, 1]]
            end
          end

          def covered?(name, id)
            needles = [name, id, id&.downcase, id&.upcase].compact.uniq
            test_sources.any? { |src| needles.any? { |needle| src.include?(needle) } }
          end

          # Read once per scan. Sixteen rule files against ~280 test files is
          # 4,500 reads without this.
          def test_sources
            @test_sources ||= Dir.glob(File.join(@test_dir, "**", "*.rb")).map do |file|
              File.read(file, encoding: "UTF-8", invalid: :replace)
            end
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        # Runtime authority lives in YAML + Ground::BootstrapDocs — not markdown under data/.
        RuleDSL.rule :RUNTIME_DOCS_YAML,
          severity: :error,
          tags: %i[CONSTITUTION DOCS],
          applies_to: %i[markdown],
          autofix: false,
          description: "runtime-read docs must be YAML — forbid stray .md under data/" do |_src, path:|
          rel = RuntimeDocsPaths.data_relative(path)
          next [] unless rel&.start_with?("data/") && rel.end_with?(".md")

          allowed = %w[
            data/SOUL.md
            data/CANON.md
            data/IDENTITY.md
          ].freeze
          next [] if allowed.include?(rel)

          target = case rel
                   when %r{\Adata/principles/} then "data/rules.yml#operator_principles"
                   when %r{\Adata/claude/} then "data/project_context.yml"
                   else "YAML runtime (rules.yml#operator_principles, patterns.yml#skills_registry, project_context.yml)"
                   end

          [finding(
            line: 1,
            message: "runtime docs belong in #{target} — delete #{rel} (see Ground::BootstrapDocs)",
          )]
        end

        module RuntimeDocsPaths
          module_function

          def data_relative(path)
            expanded = File.expand_path(path.to_s)
            root = File.expand_path(Master::ROOT)
            return unless expanded.start_with?("#{root}/")

            expanded.delete_prefix("#{root}/")
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        class LearnedSmellsRule < Rule
          def initialize(root: Master::ROOT)
            super()
            @id = "LEARNED_SMELLS"
            @description = "session-learned smell patterns from rules.yml"
            @severity = :warning
            @rule_tags = %i[LEARNED_SMELLS SESSION]
            @auto_fix = false
            @root = root
            reload_learned_smells!
          end

          def check(code, path:)
            reload_learned_smells_if_stale
            return [] if @learned_smells.empty?

            language = self.language(path)&.to_s
            @learned_smells.flat_map { |smell| findings_for_smell(smell, code, language) }
          rescue StandardError => e
            [Finding.build(rule: @id, message: "learned smell scan error — #{e.message}", line: 1,
              severity: :warning, tags: %i[LEARNED_SMELLS])]
          end

          def findings_for_smell(smell, code, language)
            return [] unless applies_to_smell?(smell, language)

            pattern = smell_pattern(smell)
            return [] unless pattern

            # A content smell is a raw regex, so on raw lines it matches its own
            # subject in prose: magic_number fired on every number in a comment
            # (6,318 findings, sampled 100% comment text) and future_tense on
            # "would"/"could" in rationale comments. Such a smell opts into
            # skip_comments and its comment-only lines are blanked to spaces
            # (length-preserving, so line numbers still land). Opt-in, because a
            # smell can legitimately mean to read a comment: sycophancy is about
            # the words, wherever they are written, and the whitespace smell this
            # was first written for had to see the raw line or every comment would
            # read as trailing space.
            source = smell["skip_comments"] ? without_comment_lines(code) : code
            source.each_line.with_index(1).filter_map do |line, line_number|
              next if line.match?(/scan:\s*intentional\b/)
              next unless line.match?(pattern)

              rule_id = smell["id"].to_s
              Finding.build(
                rule: rule_id.empty? ? @id : rule_id,
                message: smell_message(smell),
                line: line_number,
                severity: smell_severity(smell),
                tags: smell_tags(smell),
                reversibility: smell["reversibility"],
                blast_radius: smell["blast_radius"],
              )
            end
          end

          private

          def reload_learned_smells_if_stale
            return if @rules_mtime == rules_mtime

            reload_learned_smells!
          end

          def reload_learned_smells!
            @learned_smells = Array(Master.load_yaml(rules_path)&.fetch("learned_smells", [])).select { |item| item.is_a?(Hash) }
            @rules_mtime = rules_mtime
          rescue StandardError
            @learned_smells = []
            @rules_mtime = nil
          end

          def rules_path
            File.join(@root, "data", "rules.yml")
          end

          def rules_mtime
            File.exist?(rules_path) ? File.mtime(rules_path).to_i : nil
          end

          def smell_pattern(smell)
            raw = smell["pattern"] || smell["regex"] || smell["detect"]
            return unless raw

            Regexp.new(raw.to_s)
          rescue RegexpError => e
            # A learned smell whose pattern will not compile is inert law.
            Master::Ground::Swallow.log(e, context: "smell_pattern #{smell["id"]}", severity: :load_bearing)
            nil
          end

          def smell_message(smell)
            smell["message"] || smell["description"] || smell["name"] || smell["id"] || "learned smell"
          end

          def smell_severity(smell)
            (smell["severity"] || "warning").to_sym
          end

          def smell_tags(smell)
            Array(smell["tags"]).map(&:to_sym) + %i[LEARNED_SMELL]
          end

          def applies_to_smell?(smell, language)
            mediums = Array(smell["mediums"] || smell["medium"] || smell["applies_to"]).compact.map(&:to_s)
            return true if mediums.empty?
            return false if language.nil?

            mediums.include?(language)
          end
        end

        # FILE_SPRAWL — the tree's shape is conduct too. A directory holding
        # one file is a namespace bought for nothing, and a file under
        # TINY_CODE_LINES code lines is usually a concept that belongs inside
        # its owner (soul: COLLAPSE_BEFORE_ADDING — flatten, merge). The
        # 2026-08-19 census found 25 one-or-two-file directories and 34 tiny
        # files in lib/ alone; the operator's standing instruction is a clean,
        # minimal tree. Findings only — the merge itself changes requires,
        # Zeitwerk names and tests, which is the LLM fix lane's job under its
        # normal accept gates, never a mechanical rewrite.
        #
        # Out of scope by design: law/ (one rule per file until the domain-file
        # consolidation decision), lib/core (the spine's file count is a
        # ratcheted invariant in data/spine.yml), test/spec (fixture files are
        # legitimately small), and everything generated.
        class FileSprawlRule < Rule
          TINY_CODE_LINES = 25
          SKIP_RE = %r{/(?:law|core|test|spec|fixtures|templates|node_modules)/|/web/public/}
          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "FILE_SPRAWL"
            @description = "one-file directories and tiny files merge into their owners"
            @severity = :warning
            @auto_fix = false
            @rule_tags = %i[FLAT_HIERARCHY COLLAPSE_BEFORE_ADDING]
            @root = File.expand_path(root)
            @dir_entries = {}
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb")
            return [] if path.to_s.match?(SKIP_RE)
            # A tiny file can be tiny by contract: boot/paths.rb exists so four
            # files can require paths without boot order. The opt-out names its
            # reason in the file itself, where the next reader finds it.
            return [] if code.lines.first(6).any? { |l| l.include?("sprawl: deliberate") }

            dir = File.dirname(path)
            siblings, subdirs = dir_shape(dir)
            [lone_file_finding(dir, siblings, subdirs), tiny_file_finding(code, dir, siblings)].compact
          end

          private

          def lone_file_finding(dir, siblings, subdirs)
            return unless siblings == 1 && subdirs.zero? && dir != @root

            finding(
              line: 1,
              message: "FILE_SPRAWL: only file in #{relative(dir)}/ — hoist into #{relative(File.dirname(dir))}/ " \
                       "or merge into #{File.basename(dir)}.rb (flatten before adding)",
            )
          end

          def tiny_file_finding(code, dir, siblings)
            lines = CodeMetrics.code_lines(code)
            return unless lines < TINY_CODE_LINES && siblings > 1

            finding(
              line: 1,
              message: "FILE_SPRAWL: #{lines} code lines — absorb into its closest owner in #{relative(dir)}/ (merge)",
            )
          end

          def dir_shape(dir)
            @dir_entries[dir] ||= [
              Dir.glob(File.join(dir, "*.rb")).size,
              Dir.glob(File.join(dir, "*/")).size,
            ]
          end

          def relative(path) = path.delete_prefix("#{@root}/")
        end

        # PATH_PURPOSE — PATH_OWNERSHIP.yml states what every path in this tree
        # is for, its risk, and the check that governs it. Nothing read it, so a
        # new directory cost nothing and declared nothing: the 2026-08-31 session
        # created renders/sweep/, frames_final2/ and frames_final3/ without one
        # of them saying what it held. A directory with no ownership entry is a
        # namespace nobody has taken responsibility for.
        #
        # Reported per directory rather than per file, because the fix is one
        # entry, not one per member. Scratch and generated trees are out of
        # scope: they are working residue, not structure.
        class PathPurposeRule < Rule
          SKIP_RE = %r{/(?:test|spec|fixtures|node_modules|vendor|tmp|log|scratch|frames?_|renders?)/|/\.}
          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "PATH_PURPOSE"
            @description = "every directory declares its purpose in PATH_OWNERSHIP.yml"
            # error, not warning: WriteGuard blocks on veto/critical/error, and a
            # directory nobody has taken responsibility for is exactly what
            # should be refused at write time rather than reported afterwards.
            @severity = :error
            @auto_fix = false
            @rule_tags = %i[ONE_SOURCE COLLAPSE_BEFORE_ADDING]
            @root = File.expand_path(root)
          end

          def owned
            @owned ||= begin
              y = Master.load_yaml(File.join(@root, "PATH_OWNERSHIP.yml")) || {}
              Array((y["ownership"] || {}).keys)
            rescue StandardError => e
              # An unreadable ownership file must not retire the whole corpus:
              # returning [] here makes every path look owned and the scan
              # reports the tree clean having judged nothing.
              Master::Ground::Swallow.log(e, context: "PathPurposeRule.owned",
                                            severity: :load_bearing, path: File.join(@root, "PATH_OWNERSHIP.yml"))
              []
            end
          end

          def check(_code, path:)
            return [] if owned.empty?
            return [] if path.to_s.match?(SKIP_RE)

            # PATH_OWNERSHIP.yml describes MASTER's tree and says nothing about
            # its siblings, so it cannot judge them. Without this the prefix
            # strip below was a no-op for any path outside the root: `rel` stayed
            # absolute, `shallowest_gap` walked up to "", and every file in
            # RAILS, OPENBSD and STUDIO drew `PATH_PURPOSE: / has no entry`. At
            # severity :error that is a WriteGuard block, so the constitution
            # refused every write outside MASTER for as long as it stood.
            return [] unless under_root?(path)

            rel = path.to_s.delete_prefix("#{@root}/")
            dir = File.dirname(rel)
            return [] if dir == "." || covered?(rel, dir)

            # One entry covers a whole subtree, so name the shallowest gap
            # rather than every level beneath it: web/ once, not web/app/,
            # web/app/models/ and eleven more under it.
            top = shallowest_gap(dir)
            [finding(line: 1, message: "PATH_PURPOSE: #{top}/ has no entry in PATH_OWNERSHIP.yml — " \
                                       "declare its purpose and risk, or put these files under a path that has one")]
          end

          private

          def under_root?(path)
            expanded = File.expand_path(path.to_s)
            expanded == @root || expanded.start_with?(@root + File::SEPARATOR)
          end

          def shallowest_gap(dir)
            parts = dir.split("/")
            (1..parts.size).each do |n|
              candidate = parts.first(n).join("/")
              return candidate unless covered?(candidate, candidate)
            end
            dir
          end

          # A key is a file, a directory prefix, or a glob (web/public/face.part*.txt).
          def covered?(rel, dir)
            owned.any? do |key|
              k = key.to_s.delete_prefix("./")
              next true if k == rel
              next true if k.end_with?("/") && "#{dir}/".start_with?(k)
              next true if k.include?("*") && File.fnmatch?(k, rel)

              false
            end
          end
        end
      end
    end
  end
end
