# frozen_string_literal: true

require "digest"
require "prism"
require "set"

module Master
  module Review
    module Scan
      class CrossFileAnalysis
        VIRTUAL_PATH = ".master/cross_file_analysis"
        MIN_FILES = 3
        BLOCK_LINES = 5
        MAGIC_NUMBER = /(?<![\w.])-?\b(?:[2-9]|[1-9]\d{2,})\b(?![\w.])/
        CONCERN_WORDS = %w[cost auth policy cache notify notification search activity provider].freeze

        def initialize(root:)
          @root = root
        end

        def call(paths)
          files = readable_files(paths)
          findings = []
          findings.concat(duplicate_function_calls(files))
          findings.concat(duplicate_glob_patterns(files))
          findings.concat(magic_number_spread(files))
          findings.concat(copy_paste_blocks(files))
          findings.concat(structural_clones(files))
          findings.concat(parallel_hierarchies(files))
          findings.concat(scattered_config(files))
          findings.concat(sprawl(files))
          findings.concat(cyclic_dependencies(files))
          findings.empty? ? [] : [[File.join(@root, VIRTUAL_PATH), Result.ok(findings)]]
        end

        private

        def readable_files(paths)
          paths.select { |path| File.file?(path) && !Master.binary_file?(path) }
               .to_h { |path| [path, File.read(path, encoding: "UTF-8")] }
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
          Master::Ground::Swallow.log(e, context: "CrossFileAnalysis.readable_files")
          {}
        end

        def duplicate_function_calls(files)
          grouped = group_occurrences(files, /File\.read\(([^)\n]+)\)/)
          grouped.filter_map do |call, occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("CROSS_FILE_DRY", "duplicate File.read(#{call}) in #{distinct_files(occurrences)} files — extract a shared reader")
          end
        end

        def duplicate_glob_patterns(files)
          grouped = group_occurrences(files, /Dir\.glob\(([^)\n]+)\)/)
          grouped.filter_map do |pattern, occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("CROSS_FILE_DRY", "duplicate Dir.glob(#{pattern}) in #{distinct_files(occurrences)} files — extract shared glob helper")
          end
        end

        # A number is only "magic" if it is unnamed and distinctive.
        #
        # This rule produced 88 of the 231 cross-file findings on 2026-07-31 and
        # not one was actionable, for three separate reasons, all fixed here:
        #
        #   MAGIC_NUMBER matches every digit 2-9 anywhere, so "literal 8 recurs
        #   in 141 files" — array indices, loop bounds, version fragments. A
        #   single digit carries no meaning worth naming.
        #
        #   It matches four-digit years, so "literal 2026 recurs in 50 files"
        #   was the current year in comments and timestamps.
        #
        #   It counts the right-hand side of constant definitions. 32% of the
        #   occurrences behind the plausible findings were already named:
        #   PATTERN_CACHE_MAX = 512, BINARY_SAMPLE_BYTES = 512 and
        #   rag_chunk_tokens: 512 were reported as one "literal 512" needing a
        #   named constant. The rule fired on the fix it was recommending, so
        #   doing what it said made the number go up.
        NAMED_SITE = /(?:^\s*[A-Z][A-Z0-9_]*\s*=|\b[a-z_][a-z0-9_]*:\s*)\s*\z/
        YEAR_RANGE = (1900..2100)
        MAGIC_MIN = 10

        def magic_number_spread(files)
          grouped = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            code.each_line.with_index(1) do |line, number|
              line.to_enum(:scan, MAGIC_NUMBER).each do
                value = Regexp.last_match(0)
                next if magic_number_exempt?(value, prefix: Regexp.last_match.pre_match)

                grouped[value] << [path, number]
              end
            end
          end
          grouped.filter_map do |value, occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("MAGIC_NUMBER_SPREAD", "literal #{value} recurs in #{distinct_files(occurrences)} files — extract a named constant")
          end
        end

        def magic_number_exempt?(value, prefix:)
          magnitude = value.to_i.abs
          return true if magnitude < MAGIC_MIN
          return true if YEAR_RANGE.cover?(magnitude)

          # Already named: CONST = 512, or keyword: 512.
          prefix.match?(NAMED_SITE)
        end

        # Only compare files that share an extension, and only report the ones
        # that are code.
        #
        # Measured 2026-07-31 across MASTER: of 57 findings, 44 involved at
        # least one non-Ruby file and ZERO were duplicated first-party Ruby. A
        # five-line window over three JSON manifests from the same tool matches
        # because they share a schema, not because anyone copied anything, and
        # "extract a module or template" is not a thing you can do to a data
        # file. Grouping by extension stops the cross-language matches;
        # REFACTORABLE keeps the advice attached to files where it is possible.
        REFACTORABLE = %w[.rb .rake .erb .js .ts .jsx .tsx .zsh .sh].freeze

        def copy_paste_blocks(files)
          grouped = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            ext = File.extname(path)
            next unless REFACTORABLE.include?(ext)

            code.lines.each_cons(BLOCK_LINES).with_index(1) do |lines, line|
              block = normalize_block(lines)
              next if block.empty?

              # Extension in the key, so a Ruby block and a shell block that
              # normalise to the same text are never the same finding.
              grouped[Digest::SHA256.hexdigest("#{ext}\0#{block}")] << [path, line, block]
            end
          end
          grouped.values.filter_map do |occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("COPY_PASTE_BLOCK", "same #{BLOCK_LINES}+ line block recurs in #{distinct_files(occurrences)} files — extract a module or template")
          end
        end

        # copy_paste_blocks catches a block someone pasted verbatim; it misses
        # the same method rewritten with different names and literals — the clone
        # that survives a rename, which is most real DRY. Fingerprinting a def by
        # its node TYPES alone, with every identifier and literal dropped, makes
        # those two methods hash equal, so DRY fires on shared structure rather
        # than shared spelling — and it needs no model, so it runs on a keyless
        # tree where the semantic pass returns nothing.
        CLONE_RUBY = %w[.rb .rake].freeze
        CLONE_MIN_MASS = 24 # nodes in a def body; below this it is an accessor, not logic
        CLONE_MIN_FILES = 2

        def structural_clones(files)
          groups = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            next unless CLONE_RUBY.include?(File.extname(path))
            next if code.match?(/scan:\s*intentional\b/)

            each_def(Prism.parse(code).value) do |node|
              shape = node_shape(node.body)
              next if shape.length < CLONE_MIN_MASS

              groups[Digest::SHA256.hexdigest(shape.join(">"))] << [path, node.name.to_s]
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "CrossFileAnalysis.structural_clones", path:)
          end
          groups.values.filter_map do |sites|
            files_hit = sites.map(&:first).uniq
            next if files_hit.size < CLONE_MIN_FILES

            names = sites.map(&:last).uniq.first(3).join(", ")
            build("DRY", "#{sites.size} methods share one structure (#{names}) across #{files_hit.size} files — extract the shared shape")
          end
        end

        def each_def(node, &block)
          return unless node.is_a?(Prism::Node)

          yield node if node.is_a?(Prism::DefNode)
          node.compact_child_nodes.each { |child| each_def(child, &block) }
        end

        # Node classes only, pre-order. Identifiers and literals are leaf
        # attributes on the node rather than child nodes, so they never reach
        # the shape — which is exactly what lets a rename hash equal.
        def node_shape(node, acc = [])
          return acc unless node.is_a?(Prism::Node)

          acc << node.class.name.split("::").last
          node.compact_child_nodes.each { |child| node_shape(child, acc) }
          acc
        end

        def parallel_hierarchies(files)
          families = Hash.new { |hash, key| hash[key] = Set.new }
          namespaces = Set.new
          files.each do |path, code|
            # Anything written as a qualifier somewhere is a namespace. This
            # codebase opens nested modules on separate lines —
            #   module Master
            #     module Review
            #       module Scan
            # — so splitting the declaration on "::" finds nothing to learn
            # from; the evidence that Review is a namespace is that other files
            # say Master::Review::Scan when they refer into it.
            code.scan(/\b([A-Z]\w*)::/).flatten.each { |qualifier| namespaces << qualifier }
            code.scan(/^\s*(?:class|module)\s+([A-Z][\w:]+)/).flatten.each do |name|
              segments = name.split("::")
              namespaces.merge(segments[0..-2])
              families[segments.last.to_s.gsub(/(Controller|Service|Policy|Job|Rule)\z/, "")] << path
            end
          end
          families.filter_map do |stem, paths|
            next if stem.empty? || paths.size < MIN_FILES
            # A namespace is not a parallel hierarchy, it is a namespace. The
            # 2026-07-31 run led with "Master spans 441 class/module
            # hierarchies" — the root module of the codebase — and under it
            # Review (99), Ground (96), CLI (74) and Io (47), which are the
            # subsystem namespaces those 441 files nest inside. "Share a base or
            # collapse the parallel structure" is not something anyone can do
            # about a namespace, and the four of them accounted for most of the
            # rule's output.
            next if namespaces.include?(stem)

            build("PARALLEL_HIERARCHY", "#{stem} spans #{paths.size} class/module hierarchies — share a base or collapse the parallel structure")
          end
        end

        def scattered_config(files)
          grouped = group_occurrences(files, /(?:ENV\.fetch|ENV\[)\(?["']([A-Z0-9_]+)["']/)
          grouped.filter_map do |key, occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("SCATTERED_CONFIG", "ENV #{key} is read in #{distinct_files(occurrences)} files — consolidate config access")
          end
        end

        # A concern is sprawling when the CODE names it, not when the prose
        # mentions it.
        #
        # This matched /\bpolicy\b/i against whole files, comments and strings
        # included, and fired at four files. On 2026-07-31 it reported "policy"
        # across 82 files and "cache" across 73 — lib/result.rb among them,
        # because error classification legitimately talks about policy. Seven
        # findings, seven common English words. Requiring the word to appear in
        # a declaration, a method name or a constant keeps the rule's intent
        # (one concern smeared across unrelated files) and drops the prose.
        CONCERN_DECLARATION = lambda do |word|
          w = Regexp.escape(word)
          /^\s*(?:class|module)\s+\w*#{w}\w*|^\s*def\s+\w*#{w}\w*|^\s*[A-Z][A-Z0-9_]*#{w.upcase}[A-Z0-9_]*\s*=/i
        end

        def sprawl(files)
          CONCERN_WORDS.filter_map do |word|
            matcher = CONCERN_DECLARATION.call(word)
            paths = files.filter_map { |path, code| path if code.match?(matcher) }
            next if paths.uniq.size < 4 || natural_family?(paths)

            build("SPRAWL", "concern #{word.inspect} recurs in #{paths.uniq.size} unrelated files — review ownership before fixing")
          end
        end

        def cyclic_dependencies(files)
          graph = files.each_with_object({}) do |(path, code), acc|
            acc[path] = code.scan(/^\s*require_relative\s+["']([^"']+)["']/).flatten.filter_map do |rel|
              target = File.expand_path("#{rel}.rb", File.dirname(path))
              target if files.key?(target)
            end
          end
          cycle = find_cycle(graph)
          cycle ? [build("CYCLIC_DEPENDENCY", "cyclic require_relative dependency: #{cycle.map { |path| rel(path) }.join(" -> ")}")] : []
        end

        def group_occurrences(files, pattern)
          grouped = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            code.each_line.with_index(1) do |line, number|
              line.scan(pattern).flatten.each { |value| grouped[value] << [path, number] }
            end
          end
          grouped
        end

        def distinct_files(occurrences)
          occurrences.map(&:first).uniq.size
        end

        def normalize_block(lines)
          text = lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.join("\n")
          text.length < 80 ? "" : text
        end

        def natural_family?(paths)
          dirs = paths.map { |path| File.dirname(rel(path)) }.uniq
          dirs.size <= 2
        end

        def find_cycle(graph)
          visiting = Set.new
          visited = Set.new
          stack = []
          graph.each_key do |node|
            cycle = visit(node, graph:, visiting:, visited:, stack:)
            return cycle if cycle
          end
          nil
        end

        def visit(node, graph:, visiting:, visited:, stack:)
          return if visited.include?(node)
          if visiting.include?(node)
            return stack.drop_while { |entry| entry != node } + [node]
          end

          visiting << node
          stack << node
          graph.fetch(node, []).each do |child|
            cycle = visit(child, graph:, visiting:, visited:, stack:)
            return cycle if cycle
          end
          stack.pop
          visiting.delete(node)
          visited << node
          nil
        end

        def build(rule, message)
          Finding.build(rule:, line: 1, severity: :warning, message:, tags: %i[DRY SPRAWL])
        end

        def rel(path)
          path.delete_prefix("#{@root}/")
        end
      end
    end
  end
end
