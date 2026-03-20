# frozen_string_literal: true

require "open3"

module Master
  # AutoLoop — iterate on scan violations until clean or max_cycles reached.
  #
  # Cycle: scan all Ruby files → collect violations sorted by severity →
  # build full codebase context → LLM patch → syntax check → write → commit.
  # Stops when no violations remain or max_cycles is reached.
  # For full prose and structural sweep, use Sweep.
  class AutoLoop
    MAX_CYCLES       = 12
    BATCH_SIZE       = 5   # violations fixed per cycle
    CODE_PREVIEW_MAX = 4_000

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
      map = build_codebase_map

      max_cycles.times do |i|
        cycle = i + 1
        @bus&.publish("autoloop:cycle", cycle:)

        scan_result = @scanner.scan_dir(File.join(@root, "lib"), depth: :deep)
        return scan_result if scan_result.respond_to?(:err?) && scan_result.err?

        violations = extract_violations(scan_result.value!)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        violations.first(BATCH_SIZE).each do |v|
          fix = request_fix(v, map)
          apply_fix(v[:file], fix) if fix
        end

        commit(cycle) if git_dirty?
      end

      Result.ok("max cycles (#{MAX_CYCLES}) reached")
    rescue StandardError => e
      Result.err("autoloop: #{e.message}", category: :unknown)
    end

    private

    # All matching findings sorted highest severity first.
    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.respond_to?(:value!)
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .map    { |f| f.merge(file: path.delete_prefix("#{@root}/")) }
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    # Compact file map — injected into every fix prompt so the model has full
    # structural context before patching any individual file.
    def build_codebase_map
      files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                 .reject { |f| f.include?("/vendor/") }
                 .map    { |f| f.delete_prefix("#{@root}/") }
                 .sort
      "## Codebase (#{files.size} Ruby files)\n" +
        files.map { |f| "  #{f}" }.join("\n")
    end

    def request_fix(violation, map)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      src = File.read(path, encoding: "UTF-8")[0, CODE_PREVIEW_MAX]

      prompt = <<~PROMPT
        Study the full codebase map before making any change.

        #{map}

        Fix this Ruby violation in #{violation[:file]}.
        Rule: #{violation[:rule]}
        Issue: #{violation[:message]} (line #{violation[:line]})

        Do not break any interface used by other files in the codebase map.
        Return ONLY the corrected Ruby file content, no explanation.

        File:
        ```ruby
        #{src}
        ```
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

      # Syntax check before writing.
      return unless syntax_ok?(content)

      File.write(path, content, encoding: "UTF-8")
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    def syntax_ok?(content)
      IO.popen(["ruby", "-c", "--disable=all", "-e", content], err: [:child, :out]) { |io| io.read }
      $?.success?
    rescue StandardError
      false
    end

    def commit(cycle)
      Dir.chdir(@root) do
        system("git add -A lib/ 2>/dev/null")
        system("git commit -m 'autoloop: fix scan violations [cycle #{cycle}]' 2>/dev/null")
      end
    end

    def git_dirty?
      out, = Open3.capture3("git -C #{@root} status --porcelain lib/")
      !out.strip.empty?
    end
  end
end
