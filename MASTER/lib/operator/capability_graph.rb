# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "../cli/routing/provider_health"

module Operator
  class CapabilityGraph
    NODE_ORDER = %w[constitution model voice web audio rails openbsd studio].freeze

    def initialize(root:, path: File.join(root, ".master", "capabilities.json"))
      @root = root
      @path = path
    end

    def refresh(model: nil)
      payload = {
        "updated_at" => Time.now.utc.iso8601,
        "nodes" => {
          "constitution" => file_state(%w[MASTER/data/soul.yml MASTER/data/laws.yml]),
          "model" => model_state(model),
          "voice" => ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "available",
          "web" => file_state(%w[MASTER/web/public/face.css]),
          "audio" => executable_state(%w[afplay termux-media-player pactl]),
          "rails" => tree_state("RAILS"),
          "openbsd" => tree_state("OPENBSD"),
          "studio" => tree_state("STUDIO"),
        },
      }
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(payload) + "\n")
      payload
    rescue StandardError => e
      { "updated_at" => Time.now.utc.iso8601, "nodes" => {}, "error" => "#{e.class}: #{e.message}" }
    end

    def render(model: nil)
      payload = refresh(model:)
      rows = NODE_ORDER.filter_map do |name|
        state = payload.dig("nodes", name)
        next unless state
        "#{name}: #{state}#{next_action(name, state)}"
      end
      ["capabilities: #{rows.join(", ")}", payload["error"]].compact.reject(&:empty?).join("\n")
    end

    private

    def file_state(paths)
      Array(paths).all? { |path| File.file?(File.join(@root, path)) } ? "available" : "unavailable"
    end

    def tree_state(name)
      File.directory?(File.join(@root, name)) ? "available" : "unavailable"
    end

    def executable_state(names)
      names.any? { |name| executable_in_path?(name) } ? "available" : "unavailable"
    end

    def executable_in_path?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
    end

    def model_state(model)
      return "unknown" if model.to_s.empty?
      path = File.join(@root, "runtime", "telemetry", "provider_health.ndjson")
      return "unknown" unless File.file?(path)

      health = Master::CLI::Routing::ProviderHealth.new(path:)
      return "degraded" if health.unhealthy?(model)
      return "unknown" unless health.observed?(model)

      health.stale?(model, max_age_s: 120) ? "degraded" : "available"
    rescue StandardError
      "unknown"
    end

    def next_action(name, state)
      return "" if state == "available"
      case name
      when "model" then " — /model list"
      when "voice" then " — /doctor"
      when "audio" then " — /device audio"
      else " — /doctor"
      end
    end
  end
end
