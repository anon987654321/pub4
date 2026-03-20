# frozen_string_literal: true

require "open3"

module Master
  # AutoLoop — iterate on scan violations until clean or max_cycles reached.
  #
  # Cycle: scan lib+test at standard depth → collect violations by severity →
  # LLM fix (full file, no truncation) → size guard → syntax check → write → commit.
  # Stops when clean or max_cycles reached.
  class AutoLoop
    MAX_CYCLES       = 12
    BATCH_SIZE       = 3
    RATE_LIMIT_SLEEP = 15   # seconds to sleep on 429 before retrying
    MAX_FIX_RETRIES  = 3
    MIN_SIZE_RATIO   = 0.80 # reject fix if output < 80% of original file size
    MAX_FILE_BYTES   = 4_000 # skip files too large to rewrite safely (LLM token limit)

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

        scan_paths  = %w[lib test].map { |d| File.join(@root, d) }
        all_results = scan_paths.flat_map { |dir|
          res = @scanner.scan_dir(dir, depth: :standard)
          res.respond_to?(:ok?) && res.ok? ? res.value! : []
        }

        violations = extract_violations(all_results)
        return Result.ok("clean after #{cycle} cycle(s)") if violations.empty?

        yield cycle, violations if block_given?

        violations.first(BATCH_SIZE).each_with_index do |v, idx|
          sleep 15 unless idx.zero?  # pace to 4 req/min for free-tier stability
          fix = request_fix(v)
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
      }.select { |f|
        full = File.join(@root, f[:file])
        File.exist?(full) && File.size(full) <= MAX_FILE_BYTES
      }.sort_by { |f| -SEVERITY_RANK.fetch(f[:severity], 0) }
    end

    # Request a fix from the LLM. Sends FULL file — never truncates.
    # Skips files > MAX_FILE_BYTES (LLM output would be truncated, risking corruption).
    # Retries up to MAX_FIX_RETRIES on rate limit (429).
    def request_fix(violation)
      path = File.join(@root, violation[:file])
      return nil unless File.exist?(path)

      file_size = File.size(path)
      if file_size > MAX_FILE_BYTES
        @bus&.publish("autoloop:fix_skipped", file: violation[:file],
                      reason: "file too large (#{file_size} bytes)")
        return nil
      end

      src = File.read(path, encoding: "UTF-8")

      prompt = "Fix this Ruby violation in #{violation[:file]}.\n" \
               "Rule: #{violation[:rule]}\n" \
               "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
               "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
               "```ruby\n#{src}\n```"

      MAX_FIX_RETRIES.times do |attempt|
        sleep 15 if attempt > 0  # respect free-tier rate limit between retries
        begin
          return extract_code(@agent.ask(prompt).to_s)
        rescue StandardError => e
          msg = e.message.to_s
          if (msg.match?(/429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i)) &&
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

    # Safety guards: size check + syntax check before writing.
    # Rejects any fix that removes more than 20% of the original content.
    def apply_fix(rel_path, content)
      path = File.join(@root, rel_path)
      return unless File.exist?(path)

      original_size = File.size(path)
      if content.bytesize < (original_size * MIN_SIZE_RATIO).to_i
        @bus&.publish("autoloop:fix_rejected", file: rel_path,
                      reason: "too short (#{content.bytesize} vs #{original_size})")
        return
      end

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
