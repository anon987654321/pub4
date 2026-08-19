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

    def git(*args)
      out, status = Open3.capture2e("git", *args, chdir: @root)
      status.success? ? out.strip : nil
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
