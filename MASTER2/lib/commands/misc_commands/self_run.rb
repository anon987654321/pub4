# frozen_string_literal: true

module MASTER
  module Commands
    module MiscCommands
      # Full self-run across entire pub4 repo
      def selftest_full(args)
        root = MASTER.root
        apply = args&.include?("-a") || args&.include?("--apply")
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

          next unless apply && defined?(LLM) && LLM.configured?

          prompt = "Fix these violations in #{rel}:\n" \
                   "#{violations.map { |v| "- #{v[:message]}" }.join("\n")}\n\n" \
                   "Return ONLY the corrected Ruby code, no explanation."
          result = LLM.ask(prompt, stream: false)
          next unless result&.ok? && result.value[:content].to_s.include?("def ")

          File.write(file, result.value[:content])
          if system("ruby", "-c", file, out: File::NULL, err: File::NULL)
            fixed += violations.count
            puts "    + fixed"
          else
            File.write(file, code)
            puts "    - rollback (syntax error)"
          end
        end

        puts "self: #{total_violations} violations#{", #{fixed} fixed" if apply}"

        # phase 4: git status
        if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
          status = `git -C #{root} status --porcelain`.strip
          puts status.empty? ? "self: git status clean" : "self: git #{status.lines.size} uncommitted"
        end

        # phase 5: reflect via LLM
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
