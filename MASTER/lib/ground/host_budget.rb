# frozen_string_literal: true

require "open3"

module Master
  module Ground
    # OpenBSD VPS (~1GB RAM) cannot survive full-repo LLM prompts or recursive autofix.
    # Apply conservative defaults and refuse work that historically OOM-killed the host.
    module HostBudget
      CONSTRAINED_TOTAL_MB = 1_100
      HEAVY_PROMPT_BYTES = 4_000

      module_function

      def apply_defaults!
        return unless constrained?

        ENV["MASTER_SKIP_TTS"] ||= "1"
        ENV["MASTER_SKIP_BOOT_SCAN"] ||= "1"
        ENV["MASTER_BACKGROUND"] ||= "0"
        ENV["MASTER_WEB"] ||= "0" if cli_tty? && !web_explicitly_enabled?
      end

      def constrained?
        total = total_mem_mb
        total && total <= CONSTRAINED_TOTAL_MB
      end

      def total_mem_mb
        @total_mem_mb ||= detect_total_mem_mb
      end

      def detect_total_mem_mb
        if RUBY_PLATFORM.include?("openbsd")
          raw = `sysctl -n hw.physmem 2>/dev/null`.strip
          bytes = raw.to_i
          return (bytes / 1_048_576) if bytes.positive?
        end
        if File.readable?("/proc/meminfo")
          line = File.readlines("/proc/meminfo", chomp: true).find { |l| l.start_with?("MemTotal:") }
          kb = line&.split&.fetch(1, nil).to_i
          return kb / 1024 if kb.positive?
        end
        nil
      end

      def status_line
        return unless constrained?

        mb = total_mem_mb
        "host0: #{mb}MB ram — /scan lib · bin/cli --fast · avoid full-repo prompts"
      end

      def refuse_heavy_prompt?(text)
        return unless constrained?

        body = text.to_s
        return heavy_repo_message if repo_wide_request?(body)
        return "host budget: prompt too large (#{body.bytesize}B) — use /scan lib or <<" if body.bytesize > HEAVY_PROMPT_BYTES

        nil
      end

      def repo_wide_request?(text)
        t = text.to_s
        return true if t.match?(/\b(?:every|all|each)\b.*\bfiles?\b/i)
        return true if t.match?(/\b(?:analyze|analyse|audit|scan)\b.*\b(?:recursively|recursive)\b/i)
        return true if t.match?(/\b(?:autofix|autoalign|autoimplement)\b.*\b(?:MASTER|OPERATOR|repo)\b/i)
        return true if t.match?(/\b(?:MASTER|OPERATOR)\b.*\b(?:autofix|autoalign|autoimplement)\b/i)

        false
      end

      def heavy_repo_message
        mb = total_mem_mb || "low"
        "host budget: full-repo analyze/autofix OOMs on #{mb}MB — use /scan lib, /fix lib, or bin/cli --fast"
      end

      def shell_fragment_tip
        "shell tip: if CLI dies mid-line, ksh runs the leftover text — use /scan or quote paths"
      end

      def suspended_ruby_pids(user: ENV["USER"])
        return [] unless user && !user.empty?

        out, _status = Open3.capture2("ps", "x", "-o", "pid=,stat=,command=", "-U", user)
        out.each_line.filter_map do |line|
          pid, stat, *cmd = line.split
          next unless stat&.include?("T")
          next unless cmd.join(" ").match?(/bin\/cli|tts-worker/)

          pid.to_i if pid&.match?(/\A\d+\z/)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "HostBudget.suspended_ruby_pids")
        []
      end

      def reap_suspended_ruby!(user: ENV["USER"], io: $stderr)
        pids = suspended_ruby_pids(user:)
        return 0 if pids.empty?

        pids.each { |pid| Process.kill("KILL", pid) rescue Errno::ESRCH }
        io.puts "host0: reaped #{pids.size} suspended ruby (#{pids.join(", ")})"
        pids.size
      end

      def warn_or_reap_suspended!(io: $stderr)
        pids = suspended_ruby_pids
        return if pids.empty?

        if constrained?
          reap_suspended_ruby!(io:)
        else
          io.puts "cli: suspended ruby PIDs #{pids.join(", ")} — Ctrl-Z leaks memory; kill or /reap"
        end
      end

      def cli_tty?
        $stdin.tty?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "HostBudget.cli_tty?")
        false
      end

      def web_explicitly_enabled?
        ENV["MASTER_WEB"] == "1"
      end
    end

    # Enhanced HostBudgetTracker class (integrated from kimi.ai PATCH 8/9).
    # Provides mutex, events, serialization, per-file tracking.
    class HostBudgetTracker
      attr_reader :spent, :max, :warn_at, :max_per_file, :req_max, :file_spends

      def initialize(config, event_bus: nil)
        @bus = event_bus
        @max = config.budget_max.to_f
        @warn_at = config.warn_at.to_f
        @max_per_file = config.max_per_file.to_f
        @req_max = config.req_max.to_f
        @spent = 0.0
        @file_spends = Hash.new(0.0)
        @mutex = Mutex.new
      end

      def spend(amount, file: nil, model: nil)
        @mutex.synchronize do
          amount = amount.to_f
          @spent += amount
          if file
            @file_spends[file] += amount
            if @file_spends[file] > @max_per_file
              return Result.err("file budget exceeded: #{file}", category: :budget)
            end
          end
          if @spent > @max
            return Result.err("total budget exceeded: #{@spent.round(4)} > #{@max}", category: :budget)
          end
          Result.ok(spent: @spent, remaining: @max - @spent)
        end
      end

      def remaining = @mutex.synchronize { @max - @spent }
      def fraction_spent = @mutex.synchronize { @spent / @max }
      def warn_threshold? = @mutex.synchronize { @spent >= @max * @warn_at }
      def exhausted? = @mutex.synchronize { @spent >= @max }
      def reset!
        @mutex.synchronize do
          @spent = 0.0
          @file_spends.clear
        end
      end
    end
  end
end
