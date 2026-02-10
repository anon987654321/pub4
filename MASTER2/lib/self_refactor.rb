# frozen_string_literal: true

module MASTER
  # SelfRefactor - MASTER refactors its own source code
  # Uses Reflexion pattern for safety: refactor → test → verify → commit or rollback
  module SelfRefactor
    extend self

    # Files that must NEVER be auto-modified (constitutional protection)
    PROTECTED = %w[
      data/constitution.yml
      data/axioms.yml
      data/council.yml
    ].freeze

    # Files safe for self-refactoring
    SELF_TARGETS = Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb")).freeze

    def run(targets: nil, dry_run: true, auto_confirm: false)
      files = targets || SELF_TARGETS
      files = [files] unless files.is_a?(Array)

      # Filter out protected files
      files = files.reject { |f| PROTECTED.any? { |p| f.end_with?(p) } }

      results = { refactored: 0, skipped: 0, failed: 0, rollbacks: 0 }

      files.each do |file|
        next unless File.exist?(file)

        result = refactor_file(file, dry_run: dry_run, auto_confirm: auto_confirm)
        case result
        when :refactored then results[:refactored] += 1
        when :skipped    then results[:skipped] += 1
        when :failed     then results[:failed] += 1
        when :rollback   then results[:rollbacks] += 1
        end
      end

      Result.ok(results)
    end

    private

    def refactor_file(path, dry_run:, auto_confirm:)
      relative = path.sub("#{MASTER.root}/", "")
      original = File.read(path)

      # Step 1: Analyze
      if defined?(CodeReview)
        review = CodeReview.analyze(original, filename: File.basename(path))
        return :skipped if (review[:issues] || []).empty?
        UI.dim("  📝 #{relative}: #{review[:issues].size} issues") if defined?(UI)
      end

      return :skipped if dry_run

      # Step 2: Backup
      backup_path = "#{path}.bak"
      File.write(backup_path, original)

      # Step 3: Refactor via LLM (Reflexion pattern)
      prompt = <<~PROMPT
        Refactor this Ruby file. Apply these rules:
        - Methods ≤ 5 lines (Sandi Metz rules)
        - No bare rescues
        - Consistent hash key style (symbols)
        - Extract methods for any block > 5 lines
        - Keep the public API identical
        - Keep all require statements
        - frozen_string_literal comment
        
        Return ONLY the complete refactored file, no explanation.
        
        FILE: #{relative}
        ```ruby
        #{original}
        ```
      PROMPT

      result = LLM.ask(prompt, tier: :strong, stream: false)
      return :failed unless result.ok?

      # Extract code from response
      content = result.value[:content]
      refactored = content[/```ruby\n(.+?)```/m, 1] || content

      # Step 4: Syntax check
      require "open3"
      _, stderr, status = Open3.capture3("ruby", "-c", stdin_data: refactored)
      unless status.success?
        UI.warn("  ✗ #{relative}: syntax error after refactor: #{stderr[0..100]}") if defined?(UI)
        File.delete(backup_path)
        return :failed
      end

      # Step 5: Confirmation gate
      unless auto_confirm
        if defined?(ConfirmationGate)
          gate = ConfirmationGate.gate("Refactor #{relative}") { true }
          unless gate.ok?
            File.delete(backup_path)
            return :skipped
          end
        end
      end

      # Step 6: Write and verify
      File.write(path, refactored)

      # Step 7: Run self-test to verify nothing broke
      if defined?(SelfTest)
        test_result = SelfTest.run
        unless test_result.ok?
          # Rollback!
          UI.warn("  ↩ #{relative}: self-test failed, rolling back") if defined?(UI)
          File.write(path, original)
          File.delete(backup_path) if File.exist?(backup_path)
          return :rollback
        end
      end

      # Step 8: Clean up backup
      File.delete(backup_path) if File.exist?(backup_path)
      UI.dim("  ✓ #{relative}: refactored") if defined?(UI)
      :refactored
    rescue StandardError => e
      # Rollback on any error
      if File.exist?("#{path}.bak")
        File.write(path, File.read("#{path}.bak"))
        File.delete("#{path}.bak")
      end
      UI.warn("  ✗ #{relative}: #{e.message}") if defined?(UI)
      :failed
    end
  end
end
