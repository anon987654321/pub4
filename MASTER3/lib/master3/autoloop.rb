# frozen_string_literal: true

require "open3"

module Master3
  # AutoLoop — iterate on high-severity scan violations until clean.
  #
  # Cycle: scan all Ruby files → pick violations → LLM patch → syntax check → commit.
  # Stops when no violations remain or max_cycles is reached.
  # For full prose and structural sweep across every file type, use Sweep.
  class AutoLoop
    MAX_CYCLES       = 12
    CODE_PREVIEW_MAX = 4_000
    COMMIT_MSG       = "autoloop: fix scan violations [cycle %d]"

    SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

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

        scan_result = @scanner.scan_dir(@root, depth: :standard)
        return scan_result if scan_result.respond_to?(:err?) && scan_result.err?

        violations = extract_violations(scan_result.value!)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        violations.first(3).each do |v|
          fix = request_fix(v)
          apply_fix(v[:file], fix) if fix
        end

        commit(cycle) if git_dirty?
      end

      Result.ok("max cycles (#{max_cycles}) reached")
    rescue => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    private

    # Flatten scan_dir results into tagged findings, filtered by minimum severity.
    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.respond_to?(:value!)

        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .map    { |f| f.merge(file: path.delete_prefix("#{@root}/")) }
      }
    end

    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      src    = File.read(path, encoding: "UTF-8")[0, CODE_PREVIEW_MAX]
      prompt = <<~PROMPT
        Fix this Ruby violation in #{violation[:file]}.
        Rule: #{violation[:rule]}
        Issue: #{violation[:message]} (line #{violation[:line]})

        File:
        ```ruby
        #{src}
        ```

        Return ONLY the corrected Ruby file content, no explanation.
      PROMPT

      extract_code(@agent.ask(prompt).to_s)
    end

    def extract_code(text)
      return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
      return text.match(/```\n(.*?)```/m)[1].strip     if text.match?(/```\n(.*?)```/m)
      return text.strip if text.match?(/frozen_string_literal|module |class /)

      nil
    end

    def apply_fix(rel_path, content)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)

      IO.popen(["ruby", "-c", "-e", content], err: [:child, :out]) { |io| io.read }
      return unless $?.success?

      File.write(path, content, encoding: "UTF-8")
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    def commit(cycle)
      Dir.chdir(@root) do
        system("git add -A lib/ 2>/dev/null")
        system("git commit -m '#{COMMIT_MSG % cycle}' 2>/dev/null")
      end
    end

    def git_dirty?
      out, = Open3.capture3("git -C #{@root} status --porcelain lib/")
      !out.strip.empty?
    end
  end
end
