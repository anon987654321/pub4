#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "time"

$LOAD_PATH.unshift(File.expand_path("../../MASTER/lib", __dir__))
require "io/exec"
require_relative "support/interaction_campaign_adapters"

module Operator
  # Executes only explicitly mapped campaign cases. All other case/fault
  # pairings are recorded as SKIPPED with a reason; a nearby test file is not
  # evidence that an individual journey ran.
  class InteractionCampaignRunner
    include InteractionCampaignAdapters

    ROOT = File.realpath(File.expand_path("../..", __dir__))
    MANIFEST = File.join(ROOT, "RAILS", "test", "interaction_campaign_400.json")
    DEFAULT_EVIDENCE_ROOT = File.join(ROOT, ".master", "interaction_campaign_runs")
    STATES = %w[PASS FAIL BLOCKED SKIPPED].freeze
    DEFAULT_TIMEOUT = 240

    def initialize(case_ids: nil, all: false, root: ROOT, manifest_path: nil,
                   evidence_root: DEFAULT_EVIDENCE_ROOT, timeout: DEFAULT_TIMEOUT,
                   io: $stdout, executor: nil)
      @root = File.realpath(root)
      @manifest_path = manifest_path || File.join(@root, "RAILS", "test", "interaction_campaign_400.json")
      @evidence_root = File.expand_path(evidence_root, @root)
      @case_ids = Array(case_ids).map(&:to_s).reject(&:empty?).uniq
      @all = all
      @timeout = Integer(timeout).clamp(5, 1800)
      @io = io
      @executor = executor || method(:execute)
    end

    def list
      campaign.fetch("cases").each do |row|
        adapter = row["runtime_test"]
        state, description = if adapter
                               checked = command_for(row, adapter)
                               checked[:error] ? ["BLOCKED", checked[:error]] :
                                 ["READY", "#{adapter.fetch("path")}##{adapter.fetch("name")}"]
                             else
                               ["UNMAPPED", "no exact action/fault adapter"]
                             end
        @io.puts("campaign0: #{row.fetch("id")} #{state} #{description}")
      end
      0
    rescue StandardError => e
      @io.puts("campaign0: BLOCKED #{e.class}: #{e.message}")
      3
    end

    def run
      rows = selected_cases
      if rows.empty?
        @io.puts("campaign0: BLOCKED no executable cases selected")
        return 3
      end

      run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%S.%6NZ")}-#{Process.pid}"
      run_dir = File.join(@evidence_root, run_id)
      FileUtils.mkdir_p(run_dir)
      started_at = Time.now.utc.iso8601(6)
      results = rows.map { |row| run_case(row, run_dir) }
      counts = results.group_by { |row| row.fetch("status") }.transform_values(&:size)
      ledger = {
        "schema_version" => 1,
        "run_id" => run_id,
        "started_at" => started_at,
        "finished_at" => Time.now.utc.iso8601(6),
        "manifest_sha256" => campaign_manifest_sha256,
        "selected_case_count" => results.size,
        "counts" => counts,
        "results" => results
      }
      File.write(File.join(run_dir, "results.json"), "#{JSON.pretty_generate(ledger)}\n")
      @io.puts("campaign0: evidence #{run_dir}")
      @io.puts("campaign0: #{counts.sort.map { |state, count| "#{state}=#{count}" }.join(" ")}")

      return 1 if counts.fetch("FAIL", 0).positive?
      return 3 if counts.fetch("BLOCKED", 0).positive? || counts.fetch("SKIPPED", 0).positive?

      0
    rescue StandardError => e
      @io.puts("campaign0: BLOCKED #{e.class}: #{e.message}")
      3
    end

    private

    def campaign
      return @campaign if @campaign

      raw_manifest = File.read(@manifest_path, encoding: "UTF-8")
      parsed = JSON.parse(raw_manifest)
      @campaign_manifest_sha256 = Digest::SHA256.hexdigest(raw_manifest)
      raise "campaign must contain 400 cases" unless parsed.fetch("case_count") == 400 && parsed.fetch("cases").size == 400

      ids = parsed.fetch("cases").map { |row| row.fetch("id") }
      raise "campaign case IDs must be unique" unless ids.uniq.size == ids.size

      @campaign = parsed
    end

    def campaign_manifest_sha256
      campaign
      @campaign_manifest_sha256
    end

    def selected_cases
      rows = campaign.fetch("cases")
      return rows if @all
      unless @case_ids.empty?
        unknown = @case_ids - rows.map { |row| row.fetch("id") }
        raise ArgumentError, "unknown campaign case ID(s): #{unknown.join(", ")}" unless unknown.empty?

        return rows.select { |row| @case_ids.include?(row.fetch("id")) }
      end

      rows.select { |row| row.key?("runtime_test") }
    end

    def run_case(row, run_dir)
      common = {
        "case_id" => row.fetch("id"),
        "surface_id" => row.fetch("surface_id"),
        "action_id" => row.fetch("action_id"),
        "fault_mode" => row.fetch("fault_mode")
      }
      adapter = row["runtime_test"]
      unless adapter
        return common.merge(
          "status" => "SKIPPED",
          "reason" => "no exact action/fault adapter registered; no interaction executed",
          "evidence" => nil
        )
      end

      command_data = command_for(row, adapter)
      if command_data[:error]
        return common.merge(
          "status" => "BLOCKED",
          "reason" => command_data[:error],
          "evidence" => nil
        )
      end

      command = command_data.fetch(:command)
      test_path = command_data.fetch(:test_path)
      test_sha256 = Digest::SHA256.file(test_path).hexdigest
      started_at = Time.now.utc.iso8601(6)
      monotonic_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output = +""
      state = nil
      reason = nil
      exit_status = nil
      runs = assertions = failures = errors = skips = passes = nil

      begin
        output, status = @executor.call(command:, chdir: command_data.fetch(:app_root), timeout: @timeout)
        exit_status = status.exitstatus
        summary = parse_summary(output, command_data.fetch(:runner))
        if summary.nil? || summary.fetch(:runs) != 1
          state = "BLOCKED"
          reason = "test process did not report exactly one executed mapped Minitest case"
        elsif command_data.fetch(:runner) != "node_test" && summary.fetch(:assertions).to_i.zero?
          state = "BLOCKED"
          reason = "mapped test executed without assertions; no behavior was verified"
        else
          runs = summary.fetch(:runs)
          assertions = summary[:assertions]
          failures = summary.fetch(:failures)
          errors = summary.fetch(:errors)
          skips = summary.fetch(:skips)
          passes = summary[:passes]
          if skips.positive?
            state = "SKIPPED"
            reason = "mapped test was skipped"
          elsif failures.positive? || errors.positive?
            state = "FAIL"
            reason = "mapped test reported failures or errors"
          elsif command_data.fetch(:runner) == "node_test" && passes != 1
            state = "BLOCKED"
            reason = "Node test did not report exactly one passing test"
          elsif status.success? && exit_status == 0
            state = "PASS"
          else
            state = "BLOCKED"
            reason = "test process exited unsuccessfully without a failing assertion summary"
          end
        end
      rescue Master::Io::Exec::TimeoutError => e
        output = Array(e.result).first.to_s if e.result
        state = "BLOCKED"
        reason = "test process timed out after #{@timeout}s"
      rescue StandardError => e
        state = "BLOCKED"
        reason = "#{e.class}: #{e.message.to_s[0, 160]}"
      end

      test_sha256_after = begin
        Digest::SHA256.file(test_path).hexdigest
      rescue SystemCallError
        nil
      end
      if test_sha256_after != test_sha256
        state = "BLOCKED"
        reason = "mapped test source changed during execution; outcome cannot be attributed safely"
      end

      log_name = "#{row.fetch("id")}.log"
      log_output = redact_output(output.to_s)
      File.write(File.join(run_dir, log_name), log_output)
      evidence = {
        "test_path" => adapter.fetch("path"),
        "test_name" => adapter.fetch("name"),
        "runner" => command_data.fetch(:runner),
        "passes" => passes,
        "test_sha256" => test_sha256,
        "test_sha256_after" => test_sha256_after,
        "test_source_unchanged" => test_sha256_after == test_sha256,
        "command" => command,
        "exit_status" => exit_status,
        "runs" => runs,
        "assertions" => assertions,
        "failures" => failures,
        "errors" => errors,
        "skips" => skips,
        "started_at" => started_at,
        "duration_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_start) * 1000).round,
        "log" => log_name,
        "output_sha256" => Digest::SHA256.hexdigest(output.to_s),
        "log_sha256" => Digest::SHA256.hexdigest(log_output)
      }
      common.merge("status" => state, "reason" => reason, "evidence" => evidence).tap do |result|
        @io.puts("campaign0: #{result.fetch("case_id")} #{state} #{reason || adapter.fetch("name")}")
      end
    end

    def safe_repo_file(relative)
      cursor = @root
      relative.split("/").each do |part|
        return if part.empty? || part == "." || part == ".."

        cursor = File.join(cursor, part)
        return if File.symlink?(cursor)
      end
      actual = File.realpath(cursor)
      return unless actual.start_with?("#{@root}/") && File.file?(actual)

      actual
    rescue SystemCallError
      nil
    end

    def redact_output(output)
      output
        .gsub(/((?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[=:]\s*)(?:Bearer\s+)?[^\s,;]+/i, "\\1<redacted>")
        .gsub(/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,})\b/, "<redacted>")
        .gsub(/((?:set-cookie|cookie)\s*:\s*)[^\r\n]+/i, "\\1<redacted>")
    end

    def execute(command:, chdir:, timeout:)
      Master::Io::Exec.capture2e(
        { "RAILS_ENV" => "test" },
        *command,
        chdir:,
        timeout:,
        raise_on_timeout: true
      )
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { case_ids: [], all: false, list: false, timeout: Operator::InteractionCampaignRunner::DEFAULT_TIMEOUT }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby RAILS/test/run_interaction_campaign.rb [--case RI-011] [--all] [--list]"
    opts.on("--case ID", "Run one exact case adapter; repeatable") { |id| options[:case_ids] << id }
    opts.on("--all", "Record every unmapped case as SKIPPED with a reason") { options[:all] = true }
    opts.on("--list", "List mapped and unmapped cases without running tests") { options[:list] = true }
    opts.on("--timeout SECONDS", Integer, "Per-case timeout (5..1800 seconds)") { |value| options[:timeout] = value }
    opts.on("-h", "--help", "Show this help") { puts opts; exit 0 }
  end

  begin
    parser.parse!
    if options[:all] && !options[:case_ids].empty?
      raise ArgumentError, "--all and --case cannot be combined"
    end

    runner = Operator::InteractionCampaignRunner.new(
      case_ids: options[:case_ids].empty? ? nil : options[:case_ids],
      all: options[:all],
      timeout: options[:timeout]
    )
    exit(options[:list] ? runner.list : runner.run)
  rescue ArgumentError => e
    warn("campaign0: BLOCKED #{e.message}")
    warn(parser)
    exit 2
  end
end
