# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "../io/lane_quota"
require_relative "../io/lane_health"
require_relative "../io/lane_selection"

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
    TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze
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
    end

    def payload
      runs = journal_runs
      {
        processes: processes,
        runs: runs.map { |run| run_row(run) },
        mission: mission_row,
        logs: log_rows,
        commits: commit_row,
        retained: retained_rows,
        dead_lanes: ::Master::Io::LaneQuota.report,
        online: online_line,
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
      out = ["/fix status", data[:online]]
      out << "processes:"
      out << "  none running" if data[:processes].empty?
      data[:processes].each do |row|
        queue = row[:queue].empty? ? "(no tree named)" : row[:queue].join(" -> ")
        out << "  pid #{row[:pid]} up #{row[:elapsed]} queue #{queue}"
      end
      out << "runs:"
      out << "  none in the journal#{@trees.empty? ? "" : " for #{@trees.join(", ")}"}" if data[:runs].empty?
      data[:runs].each do |row|
        out << "  #{row[:state].ljust(11)} #{row[:tree]} pass #{row[:pass]}/#{row[:max_passes]} " \
               "files #{row[:files]} pid #{row[:pid]}#{row[:alive] ? " alive" : ""} started #{row[:started]}"
      end
      mission = data[:mission]
      out << "heartbeat: #{data[:heartbeat] || "none yet"}"
      out << "mission: #{mission ? "#{mission[:state]}/#{mission[:stage]} #{mission[:scope]} attempt #{mission[:attempts]} artifacts #{mission[:artifacts]}" : "none"}"
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

    def journal_runs
      data = read_json(JOURNAL)
      runs = Array(data && data["runs"])
      runs = runs.select { |run| wanted?(run["target"]) } unless @trees.empty?
      runs.last(5)
    end

    def run_row(run)
      passes = Array(run["passes"])
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
      }
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
      out, status = Open3.capture2("ps", "-axo", "pid=,etime=,command=")
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
      return unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError, SystemCallError
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
      out, status = Open3.capture2e("git", "-C", @root, *args)
      status.success? ? out.strip : nil
    end
  end
end
