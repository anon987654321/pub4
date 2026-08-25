# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "environment"
# Only "yaml" itself is behind this — requiring it does not boot the Master
# runtime, so the standalone contract above holds.
require_relative "../pub4/operator_docs"

module Pub4
  class StatusReport
    # Literal, not Master::Ground::Config::DEFAULT_WEB_PORT: this reporter is a
    # cross-repo diagnostic that must still boot when the Master runtime cannot
    # (it only requires environment.rb). Keep in sync with lib/ground/config.rb.
    DEFAULT_MASTER_WEB_PORT = 53_187
    PORTS = {
      "MASTER web" => Integer(ENV.fetch("MASTER_WEB_PORT", DEFAULT_MASTER_WEB_PORT.to_s)),
      "brgen" => 38_182,
      "amber" => 61_352,
      "bsdports" => 47_312,
    }.freeze

    # `from:`, not a positional — Environment.repo_root takes a keyword. The
    # positional call this replaces raised ArgumentError, and never showed it:
    # bin/pub4 always passes root:, so the default was never evaluated.
    def initialize(root: Environment.repo_root(from: __dir__))
      @root = root
    end

    def render(json: false)
      payload = build
      return JSON.pretty_generate(payload) if json

      render_status_lines(payload).join("\n")
    end

    def render_status_lines(payload)
      lines = []
      lines << "pub4 status"
      lines << "repo: #{payload[:repo]}"
      lines << "mode: #{payload[:mode]} (#{payload[:tree]})"
      lines << "branch: #{payload[:branch]} @ #{payload[:commit]} (#{payload[:dirty]} dirty, #{payload[:behind]} behind upstream)"
      # Dirty files grouped by top-level tree, so a session sees at a glance
      # which trees hold ANOTHER session's work-in-progress. Sessions kept
      # re-deriving "whose are the STUDIO files" from raw porcelain output;
      # the answer is one line, printed every time.
      payload[:dirty_by_tree].each do |tree, count|
        lines << "  dirty in #{tree}: #{count} file(s) — if not yours, another session's; never sweep them"
      end
      lines << "ruby: #{payload[:ruby]}#{payload[:ruby_ok] ? '' : ' — MISMATCH'}"
      lines << "debt: #{payload[:backlog_open]} open (#{payload[:backlog_source]})"
      lines << "horizon: #{payload[:horizon_count]} planned items (agent: ignore)"
      lines << ""
      lines << "services:"
      payload[:services].each { |name, state| lines << "  #{name.ljust(14)} #{state}" }
      lines << ""
      lines << "ports:"
      payload[:ports].each { |name, state| lines << "  #{name.ljust(14)} #{state}" }
      lines << ""
      lines << "next: #{payload[:next_command]}"
      lines
    end

    private

    def build
      {
        repo: @root,
        mode: Environment.mode,
        tree: Environment.tree_kind,
        branch: git("branch", "--show-current") || "unknown",
        commit: git("rev-parse", "--short", "HEAD") || "unknown",
        dirty: git("status", "--porcelain").to_s.lines.count,
        dirty_by_tree: dirty_by_tree,
        behind: git("rev-list", "--count", "HEAD..@{u}") || "0",
        ruby: Environment.ruby_label,
        ruby_ok: Environment.ruby_version_ok?,
        backlog_source:,
        backlog_open: backlog_open_count,
        horizon_count:,
        services: service_states,
        ports: port_states,
        next_command: Environment.next_command_for,
      }
    end

    def dirty_by_tree
      git("status", "--porcelain").to_s.lines
        .filter_map { |line| tree_of(line) }
        .tally.sort_by { |_, n| -n }.to_h
    end

    # Porcelain is `XY <path>`, and <path> is not always a bare path.
    #
    # git QUOTES it whenever it holds a space or a non-ASCII byte, so a dirty
    # `STUDIO/dilla/før.wav` was tallied under the tree `"STUDIO` — a quote
    # character in the name of a tree, in the line whose whole job is telling one
    # session which trees hold another session's work. A rename reports
    # `<old> -> <new>`, and the tree that matters is where the file landed.
    #
    # Not the offset: `l[3..]` is right, because quoting changes the path and not
    # the two status characters before it. Stated because the obvious reading of
    # this bug blames the slice.
    def tree_of(line)
      path = line[3..].to_s.strip
      return nil if path.empty?

      path = path.split(" -> ").last.to_s
      path = path.delete_prefix('"').delete_suffix('"')
      tree = path.split("/").first
      tree&.empty? ? nil : tree
    end

    # rstrip, not strip: in `git status --porcelain` the leading whitespace is
    # DATA. An unstaged modification is " M path", and strip ate that space off
    # the first line only — so whenever the alphabetically-first dirty file was
    # unstaged-modified, its tree lost a character and was tallied separately.
    # That is where "dirty in ASTER: 1" and "dirty in AILS: 1" came from, beside
    # a correct MASTER and RAILS: one line short, intermittent, and depending on
    # which file happened to sort first.
    #
    # Every other caller here is single-value plumbing — branch --show-current,
    # rev-parse, rev-list --count — whose output carries no leading whitespace,
    # so trimming only the tail is the same answer for them and the right one here.
    def git(*args)
      out, status = Open3.capture2e("git", *args, chdir: @root)
      status.success? ? out.rstrip : nil
    end

    def backlog_source
      Master::Pub4::OperatorDocs::DEBT_RELATIVE
    end

    # One reader for the register, in the module BootstrapDocs deploy already uses. The
    # second copy that used to live here answered the same question with its own
    # path arithmetic, and a register with two readers is how the broken one goes
    # unnoticed — it was, for weeks.
    def backlog_open_count
      Master::Pub4::OperatorDocs.open_debt_count(root: @root)
    end

    def horizon_count
      horizon = File.join(@root, "RAILS", "apps.horizon.yml")
      return 0 unless File.file?(horizon)

      data = YAML.safe_load(File.read(horizon)) || {}
      count = 0
      data.fetch("horizon", {}).each_value do |groups|
        groups.each_value do |items|
          count += items.size if items.is_a?(Array)
        end
      end
      count
    end

    def service_states
      return deployed_service_states if Environment.on_vps?

      PORTS.keys.each_with_object({}) do |name, hash|
        hash[name] = "unknown off-VPS"
      end
    end

    def deployed_service_states
      mapping = {
        "MASTER web" => "master",
        "brgen" => "brgen",
        "amber" => "amber",
        "bsdports" => "bsdports",
      }
      mapping.transform_values do |service|
        out, status = Open3.capture2e("doas", "-n", "/usr/sbin/rcctl", "check", service)
        if status.success? && out.include?("(ok)")
          "ok"
        else
          out.strip.empty? ? "failed" : out.strip
        end
      rescue StandardError
        "unknown"
      end
    end

    def port_states
      PORTS.transform_values do |port|
        Environment.port_open?(port) ? "listening :#{port}" : "closed :#{port}"
      end
    end
  end
end
