# frozen_string_literal: true

require "digest"
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
          findings.concat(parallel_hierarchies(files))
          findings.concat(scattered_config(files))
          findings.concat(sprawl(files))
          findings.concat(cyclic_dependencies(files))
          findings.empty? ? [] : [[File.join(@root, VIRTUAL_PATH), Result.ok(findings)]]
        end

        private

        def readable_files(paths)
          paths.select { |path| File.file?(path) && !File.binary?(path) }
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

        def magic_number_spread(files)
          grouped = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            code.each_line.with_index(1) do |line, number|
              line.scan(MAGIC_NUMBER).each { |value| grouped[value] << [path, number] }
            end
          end
          grouped.filter_map do |value, occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("MAGIC_NUMBER_SPREAD", "literal #{value} recurs in #{distinct_files(occurrences)} files — extract a named constant")
          end
        end

        def copy_paste_blocks(files)
          grouped = Hash.new { |hash, key| hash[key] = [] }
          files.each do |path, code|
            code.lines.each_cons(BLOCK_LINES).with_index(1) do |lines, line|
              block = normalize_block(lines)
              next if block.empty?

              grouped[Digest::SHA256.hexdigest(block)] << [path, line, block]
            end
          end
          grouped.values.filter_map do |occurrences|
            next unless distinct_files(occurrences) >= MIN_FILES

            build("COPY_PASTE_BLOCK", "same #{BLOCK_LINES}+ line block recurs in #{distinct_files(occurrences)} files — extract a module or template")
          end
        end

        def parallel_hierarchies(files)
          families = Hash.new { |hash, key| hash[key] = Set.new }
          files.each do |path, code|
            code.scan(/^\s*(?:class|module)\s+([A-Z][\w:]+)/).flatten.each do |name|
              families[name.split("::").last.to_s.gsub(/(Controller|Service|Policy|Job|Rule)\z/, "")] << path
            end
          end
          families.filter_map do |stem, paths|
            next if stem.empty? || paths.size < MIN_FILES

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

        def sprawl(files)
          CONCERN_WORDS.filter_map do |word|
            paths = files.filter_map { |path, code| path if code.match?(/\b#{Regexp.escape(word)}\b/i) }
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
            cycle = visit(node, graph: graph, visiting: visiting, visited: visited, stack: stack)
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
            cycle = visit(child, graph: graph, visiting: visiting, visited: visited, stack: stack)
            return cycle if cycle
          end
          stack.pop
          visiting.delete(node)
          visited << node
          nil
        end

        def build(rule, message)
          Finding.build(rule: rule, line: 1, severity: :warning, message: message, tags: %i[DRY SPRAWL])
        end

        def rel(path)
          path.delete_prefix("#{@root}/")
        end
      end
    end
  end
end
