# frozen_string_literal: true

module MASTER
  # MultiRefactor - Refactor entire directories with dependency-aware ordering
  # Builds a dependency graph, topologically sorts files, refactors in order
  # Handles: Ruby files, Shell scripts (with embedded Ruby), HTML files
  class MultiRefactor
    MAX_FILES = 100
    MAX_FILES_ALL = 2000
    MAX_STRICT_PASSES = 4
    MAX_SYSTEMATIC_ROUNDS = 3
    SUPPORTED_EXTENSIONS = %w[.rb .sh .html .htm .erb .yml .yaml .css .scss .sass .js .mjs .cjs .rs].freeze

    attr_reader :results, :graph

    def initialize(chamber: nil, dry_run: true, budget_cap: 2.0, force_rewrite: false, align_axioms: false, include_all_files: false)
      @chamber = chamber || Council.new
      @dry_run = dry_run
      @budget_cap = budget_cap
      @force_rewrite = force_rewrite
      @align_axioms = align_axioms
      @include_all_files = include_all_files
      @cost = 0.0
      @results = []
      @graph = {}  # file => [dependencies]
    end

    # Refactor all supported files under path
    def run(path:, pattern: nil, exclude: nil)
      Logging.dmesg_log('multi_refactor', message: 'ENTER multi_refactor.run')
      Prescan.run(path) if defined?(Prescan) && File.directory?(path)
      files = discover_files(path, pattern: pattern, exclude: exclude)
      return Result.err("No supported files found in #{path}") if files.empty?
      max_files = @include_all_files ? MAX_FILES_ALL : MAX_FILES
      return Result.err("Too many files (#{files.size} > #{max_files}). Use a more specific path.") if files.size > max_files

      # Build dependency graph
      build_dependency_graph(files)

      # Topological sort for processing order
      ordered = systematic_order(topological_sort(files))
      rounds = @dry_run ? 1 : MAX_SYSTEMATIC_ROUNDS

      UI.header("Multi-file Refactor#{@dry_run ? ' (dry run)' : ''}")
      puts "  Path: #{path}"
      puts "  Files: #{ordered.size}"
      puts "  Rounds: #{rounds}"
      puts "  Budget cap: #{UI.currency(@budget_cap)}"
      puts "  Strict rewrite: #{@force_rewrite ? 'on' : 'off'}"
      puts "  Axiom alignment: #{@align_axioms ? 'on' : 'off'}"
      puts "  Include all files: #{@include_all_files ? 'on' : 'off'}"
      puts

      bar = UI.progress(ordered.size * rounds)

      rounds.times do |round_idx|
        round_num = round_idx + 1
        round_improvements = 0
        puts UI.dim("Round #{round_num}/#{rounds}...") if rounds > 1

        ordered.each do |file|
          break if over_budget?

          bar.advance
          result = refactor_file(file)
          result[:round] = round_num
          @results << result
          round_improvements += 1 if result[:improved]
        end

        break if over_budget?
        break if round_improvements.zero?
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

      files = if @include_all_files
        Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) }
      else
        patterns = pattern ? [pattern] : SUPPORTED_EXTENSIONS.map { |ext| "**/*#{ext}" }
        patterns.flat_map { |p| Dir.glob(File.join(path, p)) }
      end

      # Default exclusions relative to the scan root.
      exclude_patterns = [
        %r{\Avendor/},
        %r{\Anode_modules/},
        %r{\A\.git/},
        %r{\Atmp/},
        %r{\Alog/},
        %r{\Avar/},
      ]
      exclude_patterns << Regexp.new(exclude) if exclude

      files.reject do |f|
        rel = f.sub(/\A#{Regexp.escape(path)}\/?/, "")
        exclude_patterns.any? { |p| rel.match?(p) }
      end
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
        deps.each { |_d| in_degree[file] += 1 }
      end

      queue = files.select { |f| in_degree[f] == 0 }
      sorted = []

      until queue.empty?
        node = queue.shift
        sorted << node

        @graph.each do |candidate, deps|
          next unless deps.include?(node)

          in_degree[candidate] -= 1
          queue << candidate if in_degree[candidate] == 0
        end
      end

      # Add any remaining files (cycles) at the end
      remaining = files - sorted
      sorted + remaining
    end

    def systematic_order(files)
      files
        .uniq
        .sort_by { |file| [priority_for(file), file] }
    end

    def priority_for(file)
      case File.extname(file)
      when ".rb" then 0
      when ".sh" then 1
      when ".yml", ".yaml" then 2
      when ".erb", ".html", ".htm" then 3
      when ".js", ".mjs", ".cjs" then 4
      when ".css", ".scss", ".sass" then 5
      when ".rs" then 6
      else 9
      end
    end

    def refactor_file(file)
      content = File.read(file)
      ext = File.extname(file)
      basename = File.basename(file)

      return { file: file, skipped: true, reason: "binary file" } if content.include?("\x00")

      # Skip files that are too large
      if content.size > 50_000
        return { file: file, skipped: true, reason: "too large (#{content.size} bytes)" }
      end

      # Use strict rewrite mode when requested, otherwise council deliberation
      result = if @force_rewrite
        strict_rewrite(content, filename: basename, ext: ext)
      else
        @chamber.deliberate(content, filename: basename)
      end

      if result.ok? && result.value[:final] && result.value[:final] != content
        cost = result.value[:cost] || 0.0
        @cost += cost

        unless @dry_run
          unless valid_refactor?(file, result.value[:final])
            return { file: file, error: "invalid syntax after refactor, not written" }
          end

          # Safety: create backup
          backup = "#{file}.bak"
          File.write(backup, content)
          File.write(file, result.value[:final])
          enforce_ruby_style!(file)

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

    def over_budget?
      @cost >= @budget_cap
    end

    def strict_rewrite(content, filename:, ext:)
      return Result.err("LLM not configured") unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?

      language = case ext
      when ".rb" then "Ruby"
      when ".sh" then "Shell"
      when ".html", ".erb" then "HTML/ERB"
      when ".yml", ".yaml" then "YAML"
      else "text"
      end

      total_cost = 0.0
      current = content.dup
      previous_violation_count = Float::INFINITY
      passes = 0

      MAX_STRICT_PASSES.times do |idx|
        passes = idx + 1
        violations = @align_axioms ? axiom_violations(current, filename) : []
        violation_count = violations.size
        violations_text = violations.first(60).map { |v| "- #{v}" }.join("\n")
        violations_text = "None provided; still enforce axioms." if violations_text.empty?

        prompt = <<~PROMPT
          Strict rewrite pass #{passes}/#{MAX_STRICT_PASSES} for #{language}.
          Rewrite this entire file end-to-end.
          Requirements:
          - Return ONLY final file contents (no markdown, no explanation).
          - Preserve behavior and interfaces unless needed for correctness/security.
          - Improve every line for clarity, consistency, and maintainability.
          - Align with project axioms and reduce violations.

          Current violation count: #{violation_count}
          Axiom issues:
          #{violations_text}

          FILE:
          #{filename}

          CONTENT:
          #{current}
        PROMPT

        result = LLM.ask(prompt, tier: :strong, stream: false)
        return Result.err("strict rewrite failed on pass #{passes}") unless result&.ok?
        total_cost += (result.value[:cost] || 0.0).to_f

        candidate = extract_code_content(result.value[:content].to_s)
        return Result.err("strict rewrite returned empty output on pass #{passes}") if candidate.strip.empty?
        return Result.err("strict rewrite produced invalid syntax on pass #{passes}") unless valid_refactor?(filename, candidate)

        new_violation_count = @align_axioms ? axiom_violations(candidate, filename).size : violation_count
        changed = candidate != current
        improved = new_violation_count < violation_count

        current = candidate if changed

        # Stop if we hit diminishing returns: no meaningful violation improvement.
        break if @align_axioms && !improved && new_violation_count >= previous_violation_count
        break unless @align_axioms

        previous_violation_count = new_violation_count
        break if new_violation_count.zero?
      end

      Result.ok(
        original: content,
        proposals: [],
        council: nil,
        final: current,
        cost: total_cost,
        rounds: passes
      )
    rescue StandardError => e
      Result.err("strict rewrite error: #{e.message}")
    end

    def extract_code_content(text)
      body = text.to_s.strip
      fenced = body.match(/\A```[a-zA-Z0-9_-]*\n(.*)\n```\z/m)
      fenced ? fenced[1] : body
    end

    def axiom_violations(content, filename)
      return [] unless defined?(Review::Enforcer)

      result = Review::Enforcer.check(content, filename: filename)
      return [] unless result.is_a?(Array)

      result.map { |v| "#{v[:axiom] || v[:axiom_id] || v[:layer]}: #{v[:message]}" }.compact
    rescue StandardError
      []
    end

    def valid_refactor?(file, content)
      return true unless defined?(SyntaxValidator)

      SyntaxValidator.valid?(file: file, content: content)
    rescue StandardError
      false
    end

    def enforce_ruby_style!(file)
      return unless File.extname(file) == ".rb"
      return unless defined?(RubocopDetector) && RubocopDetector.installed?

      system("rubocop", "-A", file, out: File::NULL, err: File::NULL)
    rescue StandardError
      nil
    end
  end
end
