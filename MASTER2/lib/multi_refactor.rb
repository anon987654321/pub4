# frozen_string_literal: true

module MASTER
  # MultiRefactor - Refactor entire directories with dependency-aware ordering
  # Builds a dependency graph, topologically sorts files, refactors in order
  # Handles: Ruby files, Shell scripts (with embedded Ruby), HTML files
  class MultiRefactor
    MAX_FILES = 100
    SUPPORTED_EXTENSIONS = %w[.rb .sh .html .erb .yml .yaml].freeze

    attr_reader :results, :graph

    def initialize(chamber: nil, dry_run: true, budget_cap: 2.0)
      @chamber = chamber || Council.new
      @dry_run = dry_run
      @budget_cap = budget_cap
      @cost = 0.0
      @results = []
      @graph = {}  # file => [dependencies]
    end

    # Refactor all supported files under path
    def run(path:, pattern: nil, exclude: nil)
      Logging.dmesg_log('multi_refactor', message: 'ENTER multi_refactor.run')
      files = discover_files(path, pattern: pattern, exclude: exclude)
      return Result.err("No supported files found in #{path}") if files.empty?
      return Result.err("Too many files (#{files.size} > #{MAX_FILES}). Use a more specific path.") if files.size > MAX_FILES

      # Build dependency graph
      build_dependency_graph(files)

      # Topological sort for processing order
      ordered = topological_sort(files)

      UI.header("Multi-file Refactor#{@dry_run ? ' (dry run)' : ''}")
      puts "  Path: #{path}"
      puts "  Files: #{ordered.size}"
      puts "  Budget cap: #{UI.currency(@budget_cap)}"
      puts

      bar = UI.progress(ordered.size)

      ordered.each_with_index do |file, idx|
        break if over_budget?

        bar.advance
        result = refactor_file(file)
        @results << result
      end

      bar.finish if bar.respond_to?(:finish)

      summary = {
        files_total: ordered.size,
        files_processed: @results.size,
        files_improved: @results.count { |r| r[:improved] },
        files_skipped: @results.count { |r| r[:skipped] },
        files_failed: @results.count { |r| r[:error] },
        total_cost: @cost,
        dry_run: @dry_run,
        results: @results
      }

      UI.header("Results")
      puts "  Processed: #{summary[:files_processed]}/#{summary[:files_total]}"
      puts "  Improved: #{summary[:files_improved]}"
      puts "  Skipped: #{summary[:files_skipped]}"
      puts "  Failed: #{summary[:files_failed]}"
      puts "  Cost: #{UI.currency_precise(summary[:total_cost])}"
      puts

      Result.ok(summary)
    rescue StandardError => e
      Result.err("MultiRefactor failed: #{e.message}")
    end

    private

    def discover_files(path, pattern: nil, exclude: nil)
      path = File.expand_path(path)

      if File.file?(path)
        return SUPPORTED_EXTENSIONS.include?(File.extname(path)) ? [path] : []
      end

      patterns = pattern ? [pattern] : SUPPORTED_EXTENSIONS.map { |ext| "**/*#{ext}" }
      files = patterns.flat_map { |p| Dir.glob(File.join(path, p)) }

      # Default exclusions
      exclude_patterns = [
        /vendor\//,
        /node_modules\//,
        /\.git\//,
        /tmp\//,
        /log\//,
        /var\//,
      ]
      exclude_patterns << Regexp.new(exclude) if exclude

      files.reject { |f| exclude_patterns.any? { |p| f.match?(p) } }
    end

    def build_dependency_graph(files)
      file_set = Set.new(files)

      files.each do |file|
        @graph[file] = []
        content = File.read(file) rescue next

        case File.extname(file)
        when ".rb"
          # Extract require_relative dependencies
          content.scan(/require_relative\s+["']([^"']+)["']/).each do |match|
            dep_path = File.expand_path(match[0] + ".rb", File.dirname(file))
            @graph[file] << dep_path if file_set.include?(dep_path)
          end
        when ".sh"
          # Extract source dependencies
          content.scan(/source\s+["']?([^"'\s]+)["']?/).each do |match|
            dep_path = File.expand_path(match[0], File.dirname(file))
            @graph[file] << dep_path if file_set.include?(dep_path)
          end
        when ".html"
          # HTML files reference each other via links
          # Capture relative links: ./file.html, file.html, ../file.html
          content.scan(/href=["'](?:\.\/)?\.\.?\/?([^"'\/]+\.html)["']/i).each do |match|
            dep_path = File.expand_path(match[0], File.dirname(file))
            @graph[file] << dep_path if file_set.include?(dep_path)
          end
        end
      end
    end

    # Kahn's algorithm for topological sort
    def topological_sort(files)
      in_degree = Hash.new(0)
      files.each { |f| in_degree[f] ||= 0 }

      @graph.each do |file, deps|
        deps.each { |d| in_degree[d] += 1 }
      end

      queue = files.select { |f| in_degree[f] == 0 }
      sorted = []

      until queue.empty?
        node = queue.shift
        sorted << node

        (@graph[node] || []).each do |dep|
          in_degree[dep] -= 1
          queue << dep if in_degree[dep] == 0
        end
      end

      # Add any remaining files (cycles) at the end
      remaining = files - sorted
      sorted + remaining
    end

    def refactor_file(file)
      content = File.read(file)
      ext = File.extname(file)
      basename = File.basename(file)

      # Skip files that are too large
      if content.size > 50_000
        return { file: file, skipped: true, reason: "too large (#{content.size} bytes)" }
      end

      # Use Council for deliberation
      result = @chamber.deliberate(content, filename: basename)

      if result.ok? && result.value[:final] && result.value[:final] != content
        cost = result.value[:cost] || 0.0
        @cost += cost

        unless @dry_run
          # Safety: create backup
          backup = "#{file}.bak"
          File.write(backup, content)
          File.write(file, result.value[:final])

          # Verify the file is still valid
          if ext == ".rb" && !valid_ruby?(file)
            # Rollback
            File.write(file, content)
            File.delete(backup) if File.exist?(backup)
            return { file: file, error: "syntax error after refactor, rolled back" }
          end

          File.delete(backup) if File.exist?(backup)
        end

        { file: file, improved: true, cost: cost, dry_run: @dry_run }
      else
        reason = result.err? ? result.error : "no changes suggested"
        { file: file, improved: false, reason: reason }
      end
    rescue StandardError => e
      { file: file, error: e.message }
    end

    def valid_ruby?(file)
      system("ruby", "-c", file, out: File::NULL, err: File::NULL)
    end

    def over_budget?
      @cost >= @budget_cap
    end
  end
end
