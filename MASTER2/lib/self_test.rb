# frozen_string_literal: true

module MASTER
  # SelfTest - Run MASTER through its own rules and standards
  module SelfTest
    class << self
      def run
        UI.header("Self-Application: MASTER through itself")
        puts "  Running full pipeline with adversarial review...\n"

        # Phase 1: Static analysis
        puts "\n  Phase 1: Static Analysis"
        static = run_static_analysis
        puts "    #{static[:passed] ? '✓' : '✗'} #{static[:message]}"

        # Phase 2: 5-layer enforcement
        puts "\n  Phase 2: 5-Layer Enforcement"
        enforcement = run_enforcement
        puts "    #{enforcement[:passed] ? '✓' : '✗'} #{enforcement[:message]}"

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
          enforcement: enforcement,
          introspection: introspection,
          file_processing: file_proc,
          pipeline_safety: pipeline_check,
          council_review: council,
        }

        print_summary(results)
        Result.ok(results)
      end

      private

      def run_static_analysis
        files = lib_files
        total_issues = 0

        files.each do |file|
          code = File.read(file)
          result = CodeReview.analyze(code, filename: File.basename(file))
          total_issues += (result[:issues] || []).size
        end

        {
          passed: total_issues < 20,
          message: "#{files.size} files, #{total_issues} issues",
          issues: total_issues,
        }
      end

      def run_enforcement
        files = lib_files
        all_violations = []

        files.each do |file|
          code = File.read(file)
          result = Enforcement.check(code, filename: File.basename(file))
          all_violations.concat(result[:violations] || [])
        end

        {
          passed: all_violations.size < 15,
          message: "#{all_violations.size} violations across 5 layers",
          violations: all_violations,
        }
      end

      def run_introspection
        files = lib_files.first(10)  # Sample for speed
        all_issues = []

        files.each do |file|
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
          status = result[:passed] ? UI.pastel.green("✓") : UI.pastel.red("✗")
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
    end
  end
end
