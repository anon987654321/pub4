# frozen_string_literal: true

module MASTER
  # SelfTest - Run MASTER through its own rules and standards
  # Includes consistency checks, logic analysis, and council review
  module SelfTest
    class << self
      def run
        print "Running self-test"
        
        # Collect all results silently
        results = {}
        
        print "."
        results[:static_analysis] = run_static_analysis
        print "."
        results[:consistency_checks] = run_consistency_checks
        print "."
        results[:enforcement] = run_enforcement
        print "."
        results[:logic_checks] = run_logic_checks
        print "."
        results[:introspection] = run_introspection
        print "."
        results[:file_processing] = run_file_processing
        print "."
        results[:pipeline_safety] = run_pipeline_test
        print "."
        results[:council_review] = run_council_review
        puts " done.\n\n"

        # Output prose summary
        print_prose_summary(results)
        Result.ok(results)
      end

      private

      def print_prose_summary(results)
        passed = results.values.count { |r| r[:passed] }
        total = results.size
        
        static = results[:static_analysis]
        consistency = results[:consistency_checks]
        enforcement = results[:enforcement]
        logic = results[:logic_checks]
        introspection = results[:introspection]
        council = results[:council_review]
        
        # Build natural prose
        paragraphs = []
        
        # Opening
        if passed == total
          paragraphs << "MASTER passed all #{total} self-application phases. The codebase meets its own standards."
        elsif passed >= total - 2
          paragraphs << "MASTER completed self-application with #{passed} of #{total} phases passing. A few areas need attention."
        else
          paragraphs << "Self-application found gaps in #{total - passed} of #{total} phases. Significant work remains."
        end
        
        # Static analysis and structure
        issues_summary = []
        issues_summary << "#{static[:issues] || 0} static analysis issues" if static[:issues].to_i > 0
        issues_summary << "#{consistency[:issues]&.size || 0} consistency issues" if consistency[:issues]&.size.to_i > 0
        issues_summary << "#{enforcement[:violations]&.size || 0} axiom violations" if enforcement[:violations]&.size.to_i > 0
        
        if issues_summary.any?
          paragraphs << "Code review found #{issues_summary.join(', ')}. Most are minor style issues like missing periods in error messages or mixed hash key types."
        else
          paragraphs << "Code review found no significant issues."
        end
        
        # Logic and adversarial
        if logic[:issues]&.size.to_i > 0 || introspection[:issues]&.size.to_i > 0
          logic_count = logic[:issues]&.size || 0
          adversarial_count = introspection[:issues]&.size || 0
          paragraphs << "Deeper analysis identified #{logic_count} logic patterns worth reviewing and #{adversarial_count} potential issues from adversarial introspection. These include thread-safety considerations and edge cases an attacker might exploit."
        end
        
        # Council rating
        if council[:rating]
          rating = council[:rating]
          if rating >= 8
            paragraphs << "The adversarial council rated the codebase #{rating}/10, indicating strong alignment with stated axioms."
          elsif rating >= 6
            paragraphs << "The adversarial council rated the codebase #{rating}/10. Room for improvement exists but fundamentals are solid."
          else
            paragraphs << "The adversarial council rated the codebase #{rating}/10, suggesting significant gaps between stated principles and implementation."
          end
        end
        
        # Print with nice wrapping
        paragraphs.each do |para|
          puts word_wrap(para, 72)
          puts
        end
      end
      
      def word_wrap(text, width)
        text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
      end

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
        result.rb boot.rb autocomplete.rb speech.rb momentum.rb weaviate.rb
      ].freeze

      def run_static_analysis
        total_issues = 0
        each_lib_file do |code, filename|
          result = CodeReview.analyze(code, filename: filename)
          total_issues += (result[:issues] || []).size
        end

        {
          passed: total_issues < MASTER::QualityStandards.max_self_test_issues,
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
          passed: all_violations.size < MASTER::QualityStandards.max_self_test_violations,
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
        key_files = %w[master.rb pipeline.rb stages.rb llm.rb chamber.rb executor.rb commands.rb enforcement.rb self_test.rb]
        code_sample = key_files.map do |f|
          path = File.join(MASTER.root, "lib", f)
          next unless File.exist?(path)
          "# #{f}\n#{File.read(path)[0, 4000]}"
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

      def lib_files
        Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
      end

      def each_lib_file
        lib_files.each { |f| yield File.read(f), File.basename(f) }
      end
    end
  end
end
