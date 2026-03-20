# frozen_string_literal: true

require "open3"

module Master
  # AutoLoop — iterate on scan violations until clean or max_cycles reached.
  #
  # Cycle: scan lib+test at standard depth → collect violations by severity →
  # build full codebase context → LLM fix (with rate-limit retry) → syntax
  # check → write → commit. Stops when clean or max_cycles reached.
  class AutoLoop
    MAX_CYCLES       = 12
    BATCH_SIZE       = 5
    CODE_PREVIEW_MAX = 4_000
    RATE_LIMIT_SLEEP = 10   # seconds to sleep on 429 before retrying
    MAX_FIX_RETRIES  = 3

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

        scan_paths  = %w[lib test].map { |d| File.join(@root, d) }
        all_results = scan_paths.flat_map { |dir|
          res = @scanner.scan_dir(dir, depth: :standard)
          res.respond_to?(:ok?) && res.ok? ? res.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        violations.first(BATCH_SIZE).each_with_index do |v, idx|
          sleep 8 unless idx.zero?  # pace to 8 req/min free-tier limit
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

    def extract_violations(dir_results)
      dir_results.flat_map { |path, r|
        next [] unless r.respond_to?(:ok?) && r.ok?
        r.value!
          .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
          .map    { |f| f.merge(file: path.delete_prefix("#{@root}/")) }
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    # Full file list injected into every fix prompt — model reads structure before patching.
    def build_codebase_map
      files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
                 .reject { |f| f.include?("/vendor/") }
                 .map    { |f| f.delete_prefix("#{@root}/") }
                 .sort
      "## Codebase (#{files.size} Ruby files)\n" +
        files.map { |f| "  #{f}" }.join("\n")
    end

    # Request a fix from the LLM. Retries up to MAX_FIX_RETRIES on rate limit (429).
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

      MAX_FIX_RETRIES.times do |attempt|
        sleep 8 if attempt > 0  # respect 8 req/min free tier between retries
        begin
          return extract_code(@agent.ask(prompt).to_s)
        rescue StandardError => e
          msg = e.message.to_s
          if (msg.match?(/429|throttl|rate.?limit|high demand|provider.?error/i)) &&
             attempt < MAX_FIX_RETRIES - 1
            sleep_sec = RATE_LIMIT_SLEEP * (attempt + 1)
            @bus&.publish("autoloop:rate_limit", sleep: sleep_sec, attempt: attempt + 1)
            sleep sleep_sec
          else
            @bus&.publish("autoloop:fix_error", file: violation[:file], error: msg[0, 120])
            return nil
          end
        end
      end
      nil
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
      return unless syntax_ok?(content)

      File.write(path, content, encoding: "UTF-8")
      @bus&.publish("autoloop:fix_applied", file: rel_path)
    end

    def syntax_ok?(content)
      require "tempfile"
      Tempfile.open(["al_chk", ".rb"]) do |f|
        f.binmode
        f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
        f.flush
        system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
      end
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
