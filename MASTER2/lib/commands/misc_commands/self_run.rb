# frozen_string_literal: true

require "open3"

module MASTER
  module Commands
    module MiscCommands
      # Unified fix pipeline: scan violations → deterministic fixer → LLM → commit.
      # Called by both `fix` (specific path) and `self-fix` (entire MASTER2 lib).
      def self_run(args)
        root    = MASTER.root
        dry_run = args.to_s.include?("--dry-run")

        # Path from args (strip flags); default to lib/ for self-improvement
        raw     = args.to_s.split.reject { |a| a.start_with?("--") }.first
        target  = if raw && (File.exist?(raw) || Dir.exist?(raw))
                    raw
                  else
                    File.join(root, "lib")
                  end

        skip = defined?(Paths::SKIP_DIRS) ? Paths::SKIP_DIRS : %w[.git vendor tmp var node_modules .bundle]
        files = if File.directory?(target)
                  Dir.glob(File.join(target, "**", "*.rb")).reject { |f| skip.any? { |d| f.include?("/#{d}/") } }
                else
                  [target]
                end

        Thread.current[:llm_quiet] = true
        ExecutionContext.current_depth = :own if defined?(ExecutionContext)

        puts "fix: #{files.size} files#{dry_run ? ' (dry-run)' : ''}"

        syntax_errors = files.reject { |f| system("ruby", "-c", f, out: File::NULL, err: File::NULL) }
        puts "fix: #{syntax_errors.any? ? "#{syntax_errors.size} syntax errors" : "syntax ok"}"

        large = files.select { |f| File.readlines(f).size > 600 rescue false }
        puts "fix: #{large.size} files >600 lines" if large.any?

        total = 0
        fixed = 0

        files.each do |file|
          code       = File.read(file)
          rel        = file.sub("#{root}/", "")
          violations = collect_violations(code, rel)
          next if violations.empty?

          total += violations.size
          puts "  #{rel}: #{violations.size}"
          violations.each { |v| puts "    #{v[:type] || v[:axiom] || v[:pattern]}: #{v[:message]}" }
          next if dry_run

          fixed += apply_fix(file, code, violations, rel)
        end

        puts "fix: #{total} violations#{fixed > 0 ? ", #{fixed} fixed" : ''}"

        git_commit_fixes(root, fixed, "fix") if !dry_run && fixed > 0

        if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
          status, = Open3.capture2("git", "-C", root, "status", "--porcelain")
          puts status.strip.empty? ? "fix: git clean" : "fix: git #{status.lines.size} uncommitted"
        end

        Result.ok("fix: #{total} violations, #{fixed} fixed")
      rescue StandardError => err
        Result.err("fix failed: #{err.message}")
      ensure
        Thread.current[:llm_quiet] = false
        ExecutionContext.current_depth = :shallow if defined?(ExecutionContext)
      end

      private

      def collect_violations(code, rel)
        v = []

        if defined?(MASTER::Enforcement)
          r = Enforcement.check(code, filename: rel) rescue nil
          v.concat(r[:violations]) if r.is_a?(Hash) && r[:violations].is_a?(Array)
        end

        if defined?(MASTER::Smells)
          r = Smells.analyze(code, rel) rescue nil
          v.concat(r[:findings] || r[:smells] || []) if r.is_a?(Hash)
          v.concat(r) if r.is_a?(Array)
        end

        if defined?(MASTER::Violations)
          r = Violations.analyze(code, path: rel) rescue nil
          if r.is_a?(Hash)
            v.concat(r[:literal] || [])
            v.concat(r[:conceptual] || [])
          end
        end

        if defined?(MASTER::CodeQuality)
          r = CodeQuality.quality_scan(rel, silent: true) rescue nil
          v.concat(r[:findings]) if r.is_a?(Hash) && r[:findings].is_a?(Array)
        end

        v
      end

      def apply_fix(file, original, violations, rel)
        # 1. Deterministic fixer
        if defined?(MASTER::Review::Fixer)
          result = MASTER::Review::Fixer.new(mode: :moderate).fix(file, violations)
          if result.ok? && result.value[:fixed].to_i > 0 &&
             system("ruby", "-c", file, out: File::NULL, err: File::NULL)
            puts "    + fixed (rules)"
            return violations.size
          elsif result.err?
            File.write(file, original) # restore on syntax failure
          end
        end

        # 2. LLM fallback
        return 0 unless defined?(LLM) && LLM.configured?

        prompt = "Fix these violations in #{rel}:\n" \
                 "#{violations.map { |v| "- #{v[:message]}" }.join("\n")}\n\n" \
                 "Return ONLY the corrected Ruby code, no explanation."
        result = LLM.ask(prompt, stream: false)
        return 0 unless result&.ok?

        new_code = result.value[:content].to_s.gsub(/\A```\w*\n/, "").gsub(/\n```\s*\z/, "")
        return 0 if new_code.strip.empty? || new_code == original
        return 0 unless MASTER::Utils.valid_ruby?(new_code)

        File.write(file, new_code)
        if system("ruby", "-c", file, out: File::NULL, err: File::NULL)
          puts "    + fixed (llm)"
          violations.size
        else
          File.write(file, original)
          puts "    - rollback"
          0
        end
      end
    end
  end
end
