# frozen_string_literal: true

module MASTER
  module Commands
    module MiscCommands
      # Full self-run across entire pub4 repo
      def self_run(args)
        root = MASTER.root
        apply = !args&.include?("--dry-run")
        lib_dir = File.join(root, "lib")
        Thread.current[:llm_quiet] = true
        ExecutionContext.current_depth = :own

        rb_files = Dir.glob(File.join(lib_dir, "**", "*.rb"))
        puts "self: #{rb_files.count} files, mode: #{apply ? 'apply' : 'dry-run'}"

        # phase 1: syntax
        syntax_errors = rb_files.reject { |f| system("ruby", "-c", f, out: File::NULL, err: File::NULL) }
        puts "self: syntax #{syntax_errors.empty? ? 'ok' : "#{syntax_errors.count} errors"}"
        syntax_errors.each { |f| puts "  #{File.basename(f)}" }

        # phase 2: sprawl
        large = rb_files.select do |f|
          File.readlines(f).size > 600
        rescue StandardError
          false
        end
        puts "self: #{large.count} files >600 lines" if large.any?
        large.each { |f| puts "  #{File.basename(f)} #{File.readlines(f).size}L" }

        # phase 3: enforcement pipeline (same as any code gets)
        total_violations = 0
        fixed = 0

        rb_files.each do |file|
          code = File.read(file)
          rel = file.sub("#{root}/", "")
          violations = []

          if defined?(MASTER::Enforcement)
            enforcement_result = begin
              Enforcement.check(code, filename: rel)
            rescue StandardError
              nil
            end
            violations.concat(enforcement_result[:violations]) if enforcement_result.is_a?(Hash) && enforcement_result[:violations].is_a?(Array)
          end

          if defined?(MASTER::Smells)
            smells_result = begin
              Smells.analyze(code, rel)
            rescue StandardError
              nil
            end
            violations.concat(smells_result[:findings] || smells_result[:smells] || []) if smells_result.is_a?(Hash)
            violations.concat(smells_result) if smells_result.is_a?(Array)
          end

          if defined?(MASTER::Violations)
            violations_result = begin
              Violations.analyze(code, path: rel, llm: (LLM if defined?(LLM) && LLM.configured?))
            rescue StandardError
              nil
            end
            found = (violations_result[:literal] || []) + (violations_result[:conceptual] || []) if violations_result.is_a?(Hash)
            violations.concat(found) if found&.any?
          end

          if defined?(MASTER::CodeQuality)
            quality_result = begin
              CodeQuality.quality_scan(rel, silent: true)
            rescue StandardError
              nil
            end
            violations.concat(quality_result[:findings]) if quality_result.is_a?(Hash) && quality_result[:findings].is_a?(Array)
          end

          next if violations.empty?

          total_violations += violations.count
          puts "  #{rel}: #{violations.count} violations"
          violations.each do |v|
            msg = v[:message].to_s.strip
            next if msg.empty?

            puts "    #{v[:axiom] || v[:type] || v[:pattern]}: #{msg}"
          end

          next unless apply

          # Prefer deterministic fixer; fall back to LLM if configured
          if defined?(MASTER::Review::Fixer)
            fixer = MASTER::Review::Fixer.new(mode: :moderate)
            result = fixer.fix(file, violations)
            # Only accept if fixer actually changed something AND syntax is valid
            if result.ok? && result.value[:fixed].to_i > 0 &&
               system("ruby", "-c", file, out: File::NULL, err: File::NULL)
              fixed += violations.count
              puts "    + fixed (fixer)"
              next
            elsif result.ok? && result.value[:fixed].to_i == 0
              # Fixer made no changes — fall through to LLM (don't restore)
              nil
            else
              File.write(file, code) # restore on syntax error
            end
          end

          next unless defined?(LLM) && LLM.configured?

          prompt = "Fix these violations in #{rel}:\n" \
                   "#{violations.map { |v| "- #{v[:message]}" }.join("\n")}\n\n" \
                   "Return ONLY the corrected Ruby code, no explanation."
          llm_result = LLM.ask(prompt, stream: false)
          next unless llm_result&.ok?

          new_code = llm_result.value[:content].to_s
          # Strip markdown fences LLMs add despite instructions
          new_code = new_code.gsub(/\A```\w*\n/, "").gsub(/\n```\s*\z/, "")
          next if new_code.strip.empty? || new_code == code
          next unless MASTER::Utils.valid_ruby?(new_code)

          File.write(file, new_code)
          if system("ruby", "-c", file, out: File::NULL, err: File::NULL)
            fixed += violations.count
            puts "    + fixed"
          else
            File.write(file, code)
            puts "    - rollback (syntax error)"
          end
        end

        puts "self: #{total_violations} violations#{", #{fixed} fixed" if apply}"

        # phase 4: git commit if fixes were applied
        git_commit_fixes(root, fixed, "self") if apply && fixed > 0

        # phase 5: git status report
        if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
          require "open3"
          status, = Open3.capture2("git", "-C", root, "status", "--porcelain")
          puts status.strip.empty? ? "self: git clean" : "self: git #{status.lines.size} uncommitted"
        end

        # phase 6: reflect via LLM
        if defined?(LLM) && LLM.configured?
          facts = "#{rb_files.count} files, #{syntax_errors.count} syntax errors, " \
                  "#{large.count} >600L, #{total_violations} violations, #{fixed} fixed"
          prompt = "You just ran self-inspection on your own codebase. " \
                   "Facts: #{facts}. " \
                   "In 5 lines or fewer: what should be improved next? Be concrete and terse."
          r = LLM.ask(prompt, stream: true)
          puts r.value[:content] if r&.ok?
        end

        Thread.current[:llm_quiet] = false
        ExecutionContext.current_depth = :shallow
        Result.ok("self complete: #{total_violations} violations, #{fixed} fixed")
      rescue StandardError => err
        Thread.current[:llm_quiet] = false
        ExecutionContext.current_depth = :shallow
        Result.err("self failed: #{err.message}")
      end
    end
  end
end
