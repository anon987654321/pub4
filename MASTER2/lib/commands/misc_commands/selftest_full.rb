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

        rb_files = Dir.glob(File.join(lib_dir, "**", "*.rb")).sort
        puts "self: #{rb_files.count} files, mode: #{apply ? 'apply' : 'dry-run'}"

        # phase 1: syntax
        syntax_errors = rb_files.select { |f| !system("ruby", "-c", f, out: File::NULL, err: File::NULL) }
        puts "self: syntax #{syntax_errors.empty? ? 'ok' : "#{syntax_errors.count} errors"}"
        syntax_errors.each { |f| puts "  #{File.basename(f)}" }

        # phase 2: sprawl
        large = rb_files.select { |f| File.readlines(f).size > 600 rescue false }
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
            r = Enforcement.check(code, filename: rel) rescue nil
            violations.concat(r[:violations]) if r.is_a?(Hash) && r[:violations].is_a?(Array)
          end

          if defined?(MASTER::Smells)
            r = Smells.analyze(code, rel) rescue nil
            violations.concat(r[:findings] || r[:smells] || []) if r.is_a?(Hash)
            violations.concat(r) if r.is_a?(Array)
          end

          if defined?(MASTER::Violations)
            r = Violations.analyze(code, path: rel, llm: (LLM if defined?(LLM) && LLM.configured?)) rescue nil
            found = (r[:literal] || []) + (r[:conceptual] || []) if r.is_a?(Hash)
            violations.concat(found) if found&.any?
          end

          if defined?(MASTER::CodeQuality)
            r = CodeQuality.quality_scan(rel, silent: true) rescue nil
            violations.concat(r[:findings]) if r.is_a?(Hash) && r[:findings].is_a?(Array)
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
          if result&.ok? && result.value[:content].to_s.include?("def ")
            File.write(file, result.value[:content])
            if system("ruby", "-c", file, out: File::NULL, err: File::NULL)
              fixed += violations.count
              puts "    + fixed"
            else
              File.write(file, code)
              puts "    - rollback (syntax error)"
            end
          end
        end

        puts "self: #{total_violations} violations#{apply ? ", #{fixed} fixed" : ""}"

        # phase 4: git status
        if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
          status = `git -C #{root} status --porcelain`.strip
          puts status.empty? ? "self: git clean" : "self: git #{status.lines.size} uncommitted"
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
        Result.ok("self complete: #{total_violations} violations, #{fixed} fixed")
      rescue StandardError => e
        Thread.current[:llm_quiet] = false
        Result.err("self failed: #{e.message}")
      end
    end
  end
end
