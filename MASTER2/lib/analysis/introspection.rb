# frozen_string_literal: true

require_relative 'introspection/self_critique'
require_relative 'introspection/self_repair'

module MASTER
  module Analysis
    # Introspection - Unified self-awareness and introspection module
    # Consolidates: SelfMap, SelfCritique, SelfRepair, SelfTest, and adversarial questioning
    # ALL code piped through MASTER2 gets the same hostile treatment
    # Whether self or user code, everything is questioned equally
    class Introspection
      class << self
        # ===================================================================
        # SECTION 1: Structure Mapping (from self_map.rb)
        # ===================================================================

        IGNORED = %w[.git node_modules vendor tmp log .bundle].freeze

        # Introspect any codebase: structure, syntax, sprawl, reflection
        def run(root = MASTER.root)
          map = generate_map(root)
          label = File.basename(root)
          puts "introspect: #{label} #{map[:lib_files].count} lib, #{map[:test_files].count} test"

          errors = map[:ruby_files].select do |f|
            !system("ruby", "-c", f, out: File::NULL, err: File::NULL)
          end
          puts "introspect: syntax #{errors.empty? ? 'ok' : "#{errors.count} errors"}"
          errors.each { |f| puts "  #{f}" }

          large = map[:ruby_files].select { |f| File.readlines(f).size > 300 rescue false }
          puts "introspect: #{large.count} files >300 lines" if large.any?
          large.each { |f| puts "  #{File.basename(f)} #{File.readlines(f).size}L" }

          if system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
            status = `git -C #{root} status --porcelain`.strip
            puts status.empty? ? "introspect: git clean" : "introspect: git #{status.lines.size} uncommitted"
          end

          if defined?(LLM) && LLM.configured?
            facts = "#{map[:lib_files].count} lib, #{map[:test_files].count} test, " \
                    "#{errors.count} syntax errors, #{large.count} >300L"
            prompt = "You inspected #{label}. Facts: #{facts}. " \
                     "In 5 lines or fewer: what should be improved? Be concrete."
            result = LLM.ask(prompt, stream: true)
            puts result.value[:content] if result&.ok?
          end

          Result.ok("introspect complete: #{map[:ruby_files].count} files, #{errors.count} errors")
        rescue StandardError => e
          Result.err("introspect failed: #{e.message}")
        end

        # Generate summary of MASTER's structure for boot display
        # @return [String] Brief summary "X lib, Y test"
        def summary(root = MASTER.root)
          map = generate_map(root)
          "#{map[:lib_files].count} lib, #{map[:test_files].count} test"
        rescue StandardError => e
          "unavailable"
        end

        # Generate complete map of MASTER's structure
        # @return [Hash] Structure map with files, ruby_files, lib_files, test_files
        def generate_map(root = MASTER.root)
          {
            files: collect_files(root, root),
            ruby_files: collect_files(root, root).select { |f| f.end_with?(".rb") },
            lib_files: collect_files(root, root).select { |f| f.include?("/lib/") && f.end_with?(".rb") },
            test_files: collect_files(root, root).select { |f| (f.include?("/test/") || f.include?("_test.rb") || f.include?("test_")) && f.end_with?(".rb") }
          }
        end

        # Generate tree string representation of directory
        # @param dir [String] Directory to scan
        # @param prefix [String] Prefix for indentation
        # @return [String] Tree representation
        def tree_string(dir = MASTER.root, prefix = "")
          result = []
          entries = Dir.entries(dir).sort.reject { |e| e.start_with?(".") || IGNORED.include?(e) }

          entries.each_with_index do |entry, idx|
            path = File.join(dir, entry)
            is_dir = File.directory?(path)

            # Only append slash for directories
            result << "#{prefix}#{entry}#{is_dir ? '/' : ''}"

            if is_dir
              result << tree_string(path, "#{prefix}  ")
            end
          end

          result.join("\n")
        end

        require_relative '../introspection/self_map'
      end

      # Instance methods for LLM-based introspection
      def initialize(llm: LLM)
        @llm = llm
      end

      def reflect_on_phase(phase, summary)
        reflection = self.class.phase_reflections[phase.to_sym]
        return nil unless reflection

        prompt = <<~PROMPT
          Phase completed: #{phase.upcase}
          Summary: #{summary}

          Reflect: #{reflection}
          Be specific. Name concrete issues, not platitudes.
          One paragraph maximum.
        PROMPT

        result = @llm.ask(prompt, stream: false)
        result.ok? ? result.value[:content] : "Reflection failed: #{result.failure}"
      end

      def hostile_question(content, context = nil)
        question = self.class.hostile_questions.sample

        prompt = <<~PROMPT
          CONTENT TO REVIEW:
          #{content[0, 2000]}
          #{"CONTEXT: #{context}" if context}

          HOSTILE QUESTION: #{question}

          If you find a genuine issue, respond:
          ISSUE: [one-line description]
          WHY: [one sentence explanation]

          If no issue found, respond:
          PASS
        PROMPT

        result = @llm.ask(prompt, stream: false)
        return nil unless result.ok?

        response = result.value[:content].to_s
        if response.include?("ISSUE:")
          {
            question: question,
            issue: response[/ISSUE:\s*(.+)/, 1],
            why: response[/WHY:\s*(.+)/, 1],
          }
        else
          nil
        end
      end

      def examine(code, filename: nil)
        prompt = <<~PROMPT
          Examine this code as a hostile reviewer.
          #{"FILE: #{filename}" if filename}

          ```
          #{code[0, 4000]}
          ```

          Answer each briefly (one line each):
          1. WORST BUG: What's the worst bug hiding here?
          2. CURSE: What will the next developer curse you for?
          3. DELETE: What would you delete entirely?
          4. MISSING: What's missing that should be obvious?
          5. VERDICT: APPROVE or REJECT (one word)
        PROMPT

        result = @llm.ask(prompt, stream: false)
        return { error: result.failure } unless result.ok?

        content = result.value[:content].to_s
        {
          worst_bug: content[/WORST BUG:\s*(.+)/, 1],
          curse: content[/CURSE:\s*(.+)/, 1],
          delete: content[/DELETE:\s*(.+)/, 1],
          missing: content[/MISSING:\s*(.+)/, 1],
          verdict: content[/VERDICT:\s*(\w+)/, 1]&.upcase,
          passed: content.include?("APPROVE"),
        }
      end

      private

      class << self
        private

        def collect_files(dir, root = dir)
          result = []

          Dir.entries(dir).each do |entry|
            next if entry.start_with?(".") || IGNORED.include?(entry)

            path = File.join(dir, entry)
            if File.directory?(path)
              result.concat(collect_files(path, root))
            else
              result << path.sub("#{root}/", "")
            end
          end

          result
        end
      end
    end
  end
end
