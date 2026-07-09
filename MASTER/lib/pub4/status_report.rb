# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "environment"

module Pub4
  class StatusReport
    PORTS = {
      "MASTER web" => Integer(ENV.fetch("MASTER_WEB_PORT", "53187")),
      "brgen" => 38_182,
      "amber" => 61_352,
      "bsdports" => 47_312,
      "hjerterom" => 38_891,
    }.freeze

    def initialize(root: Environment.repo_root(__dir__))
      @root = root
    end

    def render(json: false)
      payload = build
      return JSON.pretty_generate(payload) if json

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
      lines.join("\n")
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
        backlog_source: backlog_source,
        backlog_open: backlog_open_count,
        horizon_count: horizon_count,
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
      "OPERATOR/data/debt.yml"
    end

    def backlog_open_count
      path = File.join(@root, "OPERATOR", "data", "debt.yml")
      return 0 unless File.file?(path)

      data = YAML.safe_load(File.read(path)) || {}
      Array(data["open"]).size
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
        "hjerterom" => "hjerterom",
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