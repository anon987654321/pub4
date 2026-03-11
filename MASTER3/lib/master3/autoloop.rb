# frozen_string_literal: true

module Master3
  # AutoLoop — MASTER3 iterates on its own codebase until clean.
  # Cycle: Scan → Council review → LLM patch → Syntax check → Commit
  # Runs until no violations remain or max_cycles hit.
  class AutoLoop
    MAX_CYCLES = 12
    COMMIT_MSG = "autoloop: fix scan violations [cycle %d]"

    def initialize(agent:, scanner:, council:, root:, event_bus: nil)
      @agent   = agent
      @scanner = scanner
      @council = council
      @root    = root
      @bus     = event_bus
    end

    def run(max_cycles: MAX_CYCLES)
      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        report = @scanner.scan(@root)
        violations = report.select { |r| r[:severity] >= 2 }

        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        violations.first(3).each do |v|
          fix = request_fix(v)
          next unless fix

          apply_fix(v[:file], fix)
        end

        commit(cycle) if git_dirty?
      end

      Result.ok("max cycles (#{max_cycles}) reached")
    rescue => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    private

    def request_fix(violation)
      file    = violation[:file]
      rule    = violation[:rule]
      message = violation[:message]

      return nil unless File.exist?(File.join(@root, file))

      src = File.read(File.join(@root, file))
      prompt = "Fix this Ruby violation in #{file}.\nRule: #{rule}\nIssue: #{message}\n\nFile:\n```ruby\n#{src[0, 4000]}\n```\n\nReturn ONLY the corrected Ruby file content, no explanation."

      response = @agent.ask(prompt)
      extract_code(response.to_s)
    end

    def extract_code(text)
      if (m = text.match(/```ruby\n(.*?)```/m))
        m[1].strip
      elsif (m = text.match(/```\n(.*?)```/m))
        m[1].strip
      elsif text.include?("frozen_string_literal") || text.include?("module ") || text.include?("class ")
        text.strip
      end
    end

    def apply_fix(rel_path, content)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)

      # Syntax check before writing
      result = IO.popen(["ruby", "-c", "-e", content], err: [:child, :out]) { |io| io.read }
      return unless $?.success?

      File.write(path, content)
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    def commit(cycle)
      Dir.chdir(@root) do
        system("git add -A lib/ 2>/dev/null")
        system("git commit -m '#{COMMIT_MSG % cycle}' 2>/dev/null")
      end
    end

    def git_dirty?
      Dir.chdir(@root) do
        !`git status --porcelain lib/ 2>/dev/null`.strip.empty?
      end
    end
  end
end
