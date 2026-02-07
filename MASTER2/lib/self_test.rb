# frozen_string_literal: true

module MASTER
  # SelfTest - Run MASTER through its own rules and standards
  # Includes consistency checks, logic analysis, and council review
  module SelfTest
    class << self
      def run
        UI.header("Self-Application: MASTER through itself")
        puts "  Running full pipeline with adversarial review...\n"

        # Phase 1: Static analysis
        puts "\n  Phase 1: Static Analysis"
        static = run_static_analysis
        puts "    #{static[:passed] ? '✓' : '✗'} #{static[:message]}"

        # Phase 1.5: Consistency checks
        puts "\n  Phase 1.5: Consistency Checks"
        consistency = run_consistency_checks
        puts "    #{consistency[:passed] ? '✓' : '✗'} #{consistency[:message]}"

        # Phase 2: 5-layer enforcement
        puts "\n  Phase 2: 5-Layer Enforcement"
        enforcement = run_enforcement
        puts "    #{enforcement[:passed] ? '✓' : '✗'} #{enforcement[:message]}"

        # Phase 2.5: Logic checks
        puts "\n  Phase 2.5: Logic Analysis"
        logic = run_logic_checks
        puts "    #{logic[:passed] ? '✓' : '✗'} #{logic[:message]}"

        # Phase 3: Adversarial introspection
        puts "\n  Phase 3: Adversarial Introspection"
        introspection = run_introspection
        puts "    #{introspection[:passed] ? '✓' : '✗'} #{introspection[:message]}"

        # Phase 4: 4-phase file processing
        puts "\n  Phase 4: File Processing Analysis"
        file_proc = run_file_processing
        puts "    #{file_proc[:passed] ? '✓' : '✗'} #{file_proc[:message]}"

        # Phase 5: Pipeline safety
        puts "\n  Phase 5: Pipeline Safety"
        pipeline_check = run_pipeline_test
        puts "    #{pipeline_check[:passed] ? '✓' : '✗'} #{pipeline_check[:message]}"

        # Phase 6: Council review (uses budget)
        puts "\n  Phase 6: Council Review (LLM)"
        council = run_council_review
        puts "    #{council[:passed] ? '✓' : '✗'} #{council[:message]}"

        # Summary
        results = {
          static_analysis: static,
          consistency_checks: consistency,
          enforcement: enforcement,
          logic_checks: logic,
          introspection: introspection,
          file_processing: file_proc,
          pipeline_safety: pipeline_check,
          council_review: council,
        }

        print_summary(results)
        Result.ok(results)
      end

      private

      def run_consistency_checks
        files = lib_files
        issues = []

        files.each do |file|
          content = File.read(file)
          basename = File.basename(file)
          issues.concat(check_error_message_format(content, basename))
          issues.concat(check_exception_handling(content, basename))
        end

        {
          passed: issues.size < 5,
          message: "#{issues.size} consistency issues",
          issues: issues,
        }
      end

      def run_logic_checks
        files = lib_files
        issues = []

        files.each do |file|
          content = File.read(file)
          basename = File.basename(file)
          issues.concat(check_logic_patterns(content, basename))
        end

        {
          passed: issues.size < 3,
          message: "#{issues.size} logic issues",
          issues: issues,
        }
      end

      def check_error_message_format(content, file)
        issues = []
        messages = content.scan(/Result\.err\(["']([^"']+)["']\)/)
        messages.flatten.each do |msg|
          next if msg.start_with?(/[A-Z]/) && msg.end_with?(".")
          issues << "#{file}: Error message missing period or capitalization"
        end
        issues.first(2)  # Limit per file
      end

      def check_exception_handling(content, file)
        issues = []
        # Check for bare rescues (not rescue StandardError)
        if content.match?(/rescue\s*$/) && !BARE_RESCUE_ALLOWED.include?(file)
          issues << "#{file}: Bare rescue found"
        end
        issues
      end

      def check_logic_patterns(content, file)
        issues = []
        # Thread-unsafe memoization
        if content.match?(/\|\|=.*YAML\./) && !content.match?(/Monitor|Mutex/)
          issues << "#{file}: Potential thread-unsafe YAML memoization"
        end
        # Mixed hash key types
        symbol_keys = content.scan(/\[:\w+\]/).size
        string_keys = content.scan(/\["[^"]+"\]/).size
        if symbol_keys > 5 && string_keys > 5
          issues << "#{file}: Mixed symbol/string hash access"
        end
        issues
      end

      BARE_RESCUE_ALLOWED = %w[
        result.rb boot.rb autocomplete.rb edge_tts.rb momentum.rb weaviate.rb
      ].freeze

      def run_static_analysis
        total_issues = 0
        each_lib_file do |code, filename|
          result = CodeReview.analyze(code, filename: filename)
          total_issues += (result[:issues] || []).size
        end

        {
          passed: total_issues < 20,
          message: "#{lib_files.size} files, #{total_issues} issues",
          issues: total_issues,
        }
      end

      def run_enforcement
        all_violations = []
        each_lib_file do |code, filename|
          result = Enforcement.check(code, filename: filename)
          all_violations.concat(result[:violations] || [])
        end

        {
          passed: all_violations.size < 15,
          message: "#{all_violations.size} violations across 5 layers",
          violations: all_violations,
        }
      end

      def run_introspection
        all_issues = []
        lib_files.first(10).each do |file|
          code = File.read(file)
          result = Introspection.interrogate(code, context: { filename: File.basename(file) })
          all_issues.concat(result[:issues] || [])
        end

        {
          passed: all_issues.size < 20,
          message: "#{all_issues.size} adversarial issues found",
          issues: all_issues,
          severity: all_issues.size >= 10 ? :high : :medium,
        }
      end

      def run_file_processing
        result = FileProcessor.process_directory(File.join(MASTER.root, "lib"), dry_run: true)
        changes_needed = result[:files_changed]

        {
          passed: changes_needed < 5,
          message: "#{changes_needed} files need processing",
          details: result,
        }
      end

      def run_pipeline_test
        pipeline = Pipeline.new(stages: %i[intake compress guard])
        sample = File.read(File.join(MASTER.root, "lib", "master.rb"))[0, 500]
        result = pipeline.call({ text: "Review: #{sample}" })

        {
          passed: result.ok?,
          message: result.ok? ? "Pipeline accepts own code" : "Rejected: #{result.failure}",
        }
      end

      def run_council_review
        # Build code sample from key files
        key_files = %w[master.rb pipeline.rb stages.rb llm.rb chamber.rb]
        code_sample = key_files.map do |f|
          path = File.join(MASTER.root, "lib", f)
          next unless File.exist?(path)
          "# #{f}\n#{File.read(path)[0, 2000]}"
        end.compact.join("\n\n---\n\n")

        axiom_list = DB.axioms.map { |a| "- #{a[:name] || a[:id]}" }.join("\n")

        prompt = <<~PROMPT
          You are MASTER v#{VERSION}, reviewing your own source.
          
          AXIOMS: #{axiom_list}
          
          Review this code against axioms. Rate self-alignment 1-10.
          Be brutally honest.
          
          CODE:
          #{code_sample[0, 12_000]}
        PROMPT

        result = LLM.ask(prompt, stream: false)

        if result.ok?
          response = result.value[:content].to_s
          rating_match = response.match(/(\d+)\s*\/\s*10|rating[:\s]+(\d+)/i)
          rating = rating_match ? (rating_match[1] || rating_match[2]).to_i : 5

          puts "\n    Rating: #{rating}/10"

          {
            passed: rating >= 7,
            message: "Council rated #{rating}/10",
            rating: rating,
          }
        else
          { passed: false, message: "LLM error: #{result.failure}" }
        end
      rescue StandardError => e
        { passed: false, message: "Failed: #{e.message}" }
      end

      def print_summary(results)
        puts "\n  " + ("=" * 50)
        puts "  SELF-APPLICATION SUMMARY"
        puts "  " + ("=" * 50)

        passed = results.values.count { |r| r[:passed] }
        total = results.size

        results.each do |name, result|
          status = result[:passed] ? UI.pastel.green(UI.icon(:success)) : UI.pastel.red(UI.icon(:failure))
          puts "  #{status} #{name.to_s.tr('_', ' ').capitalize}"
        end

        puts "\n  #{passed}/#{total} phases passed"

        if passed == total
          UI.success("MASTER meets its own standards")
        else
          UI.warn("Self-application found #{total - passed} gaps")
        end
      end

      def lib_files
        Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
      end

      def each_lib_file
        lib_files.each { |f| yield File.read(f), File.basename(f) }
      end
    end
  end
end
