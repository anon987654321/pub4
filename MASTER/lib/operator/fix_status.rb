# frozen_string_literal: true

require "json"
require_relative "../io/exec"
require "time"
require_relative "../io/lane_quota"
require_relative "../io/lane_health"
require_relative "../io/lane_selection"
require_relative "../boot/paths"
require_relative "../fix/run_journal"

module Operator
  # One screen about /fix, read from what /fix already writes: the run journal
  # (.master/fix_runs.json), the mission (.master/mission.json), the per-tree
  # logs bin/fix-here leaves in .master/, the process table and git. It writes
  # nothing and boots nothing, so it answers while a run is mid-flight and
  # while the runtime cannot start.
  #
  # The target queue exists only as a dmesg line, so it is rebuilt from the
  # arguments of the live /fix process the way dispatch_fix reads them: a
  # string of governed trees runs in the order it was typed.
  class FixStatus
    TREES = MasterPaths::TREES
    JOURNAL = "MASTER/.master/fix_runs.json"
    MISSION = "MASTER/.master/mission.json"
    LOG_GLOB = "MASTER/.master/fix-*.log"
    HEARTBEAT = %r{\Afix0: pass \d+/\d+ }
    HEARTBEAT_WINDOW = 65_536
    TEMP_WORKTREE = /pub4-master-fix-/

    def initialize(root:, trees: [], now: Time.now)
      @root = File.expand_path(root)
      @trees = trees.map(&:to_s)
      @now = now
      @read_errors = {}
      @run_journal = Master::Fix::RunJournal.new(root: File.join(@root, "MASTER"))
    end

    def payload
      runs = journal_runs
      {
        processes: processes,
        runs: runs.map { |run| run_row(run) },
        mission: mission_row,
        read_errors: @read_errors.dup,
        logs: log_rows,
        commits: commit_row,
        retained: retained_rows,
        dead_lanes: ::Master::Io::LaneQuota.report,
        online: online_line,
        primary: primary_line,
        heartbeat: heartbeat_line,
      }
    end

    def render(json: false)
      data = payload
      return JSON.pretty_generate(data) if json

      lines(data).join("\n")
    end

    # Queue as /fix received it: governed trees only, typed order, no repeats.
    def self.queue_from(command)
      tokens = command.to_s.split(/\s+/).drop_while { |token| token != "/fix" }.drop(1)
      named = tokens.reject { |token| token.start_with?("-") }
      return [] unless named.any? && named.all? { |token| TREES.include?(token) }

      named.uniq
    end

    private

    def lines(data)
      out = ["/fix status", data[:online], data[:primary]]
      out << "processes:"
      out << "  none running" if data[:processes].empty?
      data[:processes].each do |row|
        queue = row[:queue].empty? ? "(no tree named)" : row[:queue].join(" -> ")
        out << "  pid #{row[:pid]} up #{row[:elapsed]} queue #{queue}"
      end
      out << "runs:"
      if data[:runs].empty?
        journal_error = data[:read_errors][JOURNAL]
        out << if journal_error
                 "  unavailable (#{journal_error})"
               else
                 "  none in the journal#{@trees.empty? ? "" : " for #{@trees.join(", ")}"}"
               end
      end
      data[:runs].each do |row|
        out << "  #{row[:state].ljust(11)} #{row[:tree]} pass #{row[:pass]}/#{row[:max_passes]} " \
               "files #{row[:files]} pid #{row[:pid]}#{row[:alive] ? " alive" : ""} started #{row[:started]}"
        out << "    result: #{row[:message]}" unless row[:message].empty?
        out << "    receipt: #{row[:receipt]}"
        out << "    assessment: #{row[:assessment_proof]}"
        out << "    finished: #{row[:finished]}" unless row[:finished].empty?
      end
      mission = data[:mission]
      out << "heartbeat: #{data[:heartbeat] || "none yet"}"
      mission_error = data[:read_errors][MISSION]
      out << if mission_error
               "mission: unavailable (#{mission_error})"
             else
               "mission: #{mission ? "#{mission[:state]}/#{mission[:stage]} #{mission[:scope]} attempt #{mission[:attempts]} artifacts #{mission[:artifacts]}" : "none"}"
             end
      out << "logs:"
      out << "  none" if data[:logs].empty?
      data[:logs].each { |row| out << "  #{row[:name]} #{row[:age]} ago: #{row[:last]}" }
      commits = data[:commits]
      out << "commits: #{commits[:ahead]} ahead of origin/main on #{commits[:branch]}, #{commits[:pushed] ? "pushed" : "not pushed"}"
      out << "dead lanes:"
      out << "  none" if data[:dead_lanes].empty?
      data[:dead_lanes].each { |row| out << "  #{row}" }
      out << "retained:"
      out << "  no temp worktrees or branches" if data[:retained].empty?
      data[:retained].each do |row|
        out << "  #{row[:branch]} #{row[:path] || "(no worktree)"} #{row[:ahead]} commit(s), " \
               "#{row[:pushed] ? "pushed" : "not pushed"}#{row[:dirty] ? ", #{row[:dirty]} dirty" : ""}"
      end
      out
    end

    # The first catalogue lane that is neither dead nor a local model with its daemon down.
    def online_line
      health = ::Master::Io::LaneHealth
      daemon = nil
      down = lambda do |model|
        health.dead?(model) || (health.local_model?(model) && !(daemon = daemon.nil? ? health.ollama_up? : daemon))
      end
      health.line(::Master::Io::LaneSelection.catalogue, refuses: down)
    end

    def primary_line
      ::Master::Io::LaneSelection.primary_report(saved: ::Master::Ground::Config.new(::Master::ROOT)["model"])
    rescue StandardError => e
      "primary: unknown (#{e.class})"
    end

    def journal_runs
      data = read_json(JOURNAL)
      runs = Array(data && data["runs"])
      runs = runs.select { |run| wanted?(run["target"]) } unless @trees.empty?
      runs.last(5)
    end

    def run_row(run)
      passes = Array(run["passes"])
      assessment_details = assessment_proof_details(run)
      {
        id: run["id"].to_s[0, 8],
        state: run["state"].to_s,
        tree: relative(run["target"]),
        pass: passes.map { |row| row["pass"].to_i }.max.to_i,
        max_passes: run["max_passes"].to_i,
        files: Array(run["files"]).size,
        pid: run["pid"],
        alive: run["state"] == "active" && alive?(run["pid"]),
        started: run["started_at"].to_s,
        finished: run["finished_at"].to_s,
        message: run["message"].to_s.gsub(/\s+/, " ").strip[0, 180],
        receipt: receipt_summary(run["evidence"]),
        assessment_proof: assessment_proof_summary(assessment_details),
        assessment_details: assessment_details,
      }
    end

    # Assessment integrity is read through the same verifier that /fix uses
    # before DONE. Preserve structured details for JSON/API consumers as well.
    def assessment_proof_details(run)
      receipt = run["assessment_receipt"]
      return { "status" => "not_recorded" } unless receipt.is_a?(Hash)

      @run_journal.verify_assessment_report(run["id"])
    rescue StandardError => e
      { "status" => "unavailable", "error_class" => e.class.name }
    end

    def assessment_proof_summary(verification)
      state = verification["status"].to_s
      return "not recorded" if state == "not_recorded"
      return "unavailable" if state == "unavailable"
      return "unverified (#{state})" unless state == "verified"

      matrix = verification["matrix_status"].to_s
      digest = verification["sha256"].to_s[0, 12]
      summary = verification["matrix_summary"] || {}
      surface = verification["surface_coverage"] || {}
      unless matrix == "complete"
        counts = "cells=#{summary["recorded_cells"]}/#{summary["expected_cells"]} " \
          "pending=#{summary["pending_cells"]} inconclusive=#{summary["inconclusive_cells"]} findings=#{summary["finding_cells"]}"
        cell = Array(verification["blockers"]).first
        surface_blocker = Array(surface["blockers"]).first
        detail = if surface_blocker
                   "surface #{surface_blocker["surface"]}=#{surface_blocker["status"]}: #{surface_blocker["reason"]}".strip
                 elsif cell
                   "#{cell["law"]}/#{cell["stream"]}/#{cell["surface"]}: #{cell["reason"]}".strip
                 else
                   "no cell-level or surface blocker detail"
                 end
        surface_counts = "surface=#{surface["measured"]}/#{surface["expected"]}"
        return "verified matrix=#{matrix} #{counts} #{surface_counts}; next=#{detail[0, 100]} sha256=#{digest}"
      end

      "verified complete surface=#{surface["status"]} #{surface["measured"]}/#{surface["expected"]} sha256=#{digest}"
    end

    # The receipt is convergence evidence, not proof of deployment, playback or
    # external-provider behavior. Keep it compact and preserve the distinction.
    def receipt_summary(evidence)
      return "not recorded" unless evidence.is_a?(Hash) && !evidence.empty?

      fields = []
      fields << "observations=#{evidence["observations"]}" if evidence.key?("observations")
      fields << "files=#{evidence["files_observed"]}" if evidence.key?("files_observed")
      fields << "findings=#{evidence["findings"]}" if evidence.key?("findings")
      fields << "delta=#{evidence["quality_delta"]}" if evidence.key?("quality_delta")
      %w[finding_digest snapshot_digest authority_digest].each do |key|
        value = evidence[key]
        fields << "#{key.delete_suffix("_digest")}=#{value[0, 12]}" if value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
      end
      fields.empty? ? "recorded (no recognized fields)" : "recorded (#{fields.join(", ")})"
    end

    def mission_row
      record = read_json(MISSION)
      return unless record && (@trees.empty? || wanted?(record["scope"]))

      {
        state: record["state"], stage: record["stage"], scope: record["scope"],
        attempts: record["attempt_count"].to_i, artifacts: Array(record["artifacts"]).size
      }
    end

    def log_rows
      Dir.glob(File.join(@root, LOG_GLOB)).filter_map do |path|
        tree = File.basename(path)[/\Afix-(.+)\.log\z/, 1]
        next unless @trees.empty? || @trees.include?(tree)

        { name: File.basename(path), age: age(File.mtime(path)), last: last_line(path) }
      end.sort_by { |row| row[:name] }
    end

    # The newest RunPulse line in any tree's log: the run's own account of where it is.
    def heartbeat_line
      Dir.glob(File.join(@root, LOG_GLOB)).sort_by { |path| -File.mtime(path).to_f }.each do |path|
        tail = File.open(path, "rb") { |file| file.seek([File.size(path) - HEARTBEAT_WINDOW, 0].max) && file.read }.to_s
        line = tail.force_encoding("UTF-8").scrub.lines.reverse.find { |row| row.match?(HEARTBEAT) }
        return line.strip if line
      end
      nil
    rescue SystemCallError
      nil
    end

    def commit_row
      branch = git("branch", "--show-current").to_s
      ahead = git("rev-list", "--count", "origin/main..HEAD").to_i
      { branch: branch, ahead: ahead, pushed: ahead.zero? }
    end

    # Temp worktrees /fix keeps when a run fails, and the master/fix-* branches
    # it pushes. A branch counts as pushed when origin holds its head.
    def retained_rows
      paths = {}
      current = nil
      git("worktree", "list", "--porcelain").to_s.each_line do |line|
        case line
        when /\Aworktree (.+)/ then current = Regexp.last_match(1).strip
        when %r{\Abranch refs/heads/(.+)} then paths[Regexp.last_match(1).strip] = current
        end
      end
      branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/master/fix-*").to_s.split
      branches |= paths.keys.select { |name| paths[name].to_s.match?(TEMP_WORKTREE) }
      branches.map do |branch|
        path = paths[branch]
        head = git("rev-parse", branch)
        remote = git("rev-parse", "--verify", "--quiet", "origin/#{branch}")
        {
          branch: branch,
          path: path,
          ahead: git("rev-list", "--count", "origin/main..#{branch}").to_i,
          pushed: !remote.nil? && remote == head,
          dirty: path && File.directory?(path) ? git("-C", path, "status", "--porcelain").to_s.lines.size : nil,
        }
      end
    end

    def processes
      out, status = Master::Io::Exec.capture2("ps", "-axo", "pid=,etime=,command=")
      return [] unless status.success?

      out.each_line.filter_map do |line|
        pid, elapsed, command = line.strip.split(/\s+/, 3)
        next unless command.to_s.match?(%r{(?:\A|/)master(?:\.rb)?\s+/fix(?:\s|\z)}) || command.to_s.match?(%r{bin/master\s+/fix})
        next if pid.to_i == Process.pid

        queue = self.class.queue_from(command)
        next unless @trees.empty? || queue.empty? || (queue & @trees).any?

        { pid: pid.to_i, elapsed: elapsed, queue: queue }
      end
    end

    def wanted?(target)
      tree = relative(target).split("/").first
      @trees.include?(tree)
    end

    def relative(target)
      value = target.to_s
      value.start_with?(@root) ? value.delete_prefix("#{@root}/") : value
    end

    def alive?(pid)
      Process.kill(0, pid.to_i)
      true
    rescue Errno::ESRCH, Errno::EPERM, RangeError, TypeError
      false
    end

    def read_json(relative_path)
      path = File.join(@root, relative_path)
      if File.symlink?(path)
        @read_errors[relative_path] = "refusing symlink"
        return
      end
      return unless File.file?(path)

      JSON.parse(File.read(path, encoding: "UTF-8"))
    rescue JSON::ParserError => e
      @read_errors[relative_path] = "invalid JSON: #{e.message.gsub(/\s+/, " ")[0, 100]}"
      nil
    rescue SystemCallError => e
      @read_errors[relative_path] = "#{e.class}: #{e.message.to_s.gsub(/\s+/, " ")[0, 100]}"
      nil
    end

    def last_line(path)
      File.readlines(path, encoding: "UTF-8", invalid: :replace).reverse.find { |line| !line.strip.empty? }.to_s.strip[0, 120]
    rescue SystemCallError
      ""
    end

    def age(time)
      seconds = (@now - time).to_i
      return "#{seconds}s" if seconds < 120
      return "#{seconds / 60}m" if seconds < 7200

      "#{seconds / 3600}h"
    end

    def git(*args)
      out, status = Master::Io::Exec.capture2e("git", "-C", @root, *args)
      status.success? ? out.strip : nil
    end
  end
end
