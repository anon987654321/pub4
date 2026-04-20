# frozen_string_literal: true

module Master
  # Standing Orders — persistent authority programs that execute autonomously.
  # Inspired by OpenClaw's "standing orders" concept: named programs with
  # defined scope, triggers, and approval gates that run on schedule or
  # in response to events without requiring per-request user confirmation.
  #
  # Storage: data/standing_orders.yml
  # Each order: { name, description, trigger, interval_s, last_run_at, enabled, command }
  class StandingOrders
    STORE_PATH = File.join(Master::ROOT, "data", "standing_orders.yml")

    BUILTIN_ORDERS = [
      {
        name:        "nightly_dreams",
        description: "Consolidate memories during low-activity periods",
        trigger:     "scheduled",
        interval_s:  86_400,
        command:     "dreams consolidate",
        enabled:     true
      },
      {
        name:        "weekly_scan",
        description: "Weekly codebase axiom scan for regressions",
        trigger:     "scheduled",
        interval_s:  604_800,
        command:     "scan",
        enabled:     false
      }
    ].freeze

    def initialize(pipeline: nil, event_bus: nil)
      @pipeline  = pipeline
      @bus       = event_bus
      @orders    = load_orders
    end

    # Returns orders due to run (trigger: scheduled, interval elapsed).
    def due
      now = Time.now.to_i
      @orders.select do |o|
        o["enabled"] &&
          o["trigger"] == "scheduled" &&
          (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
      end
    end

    # Run all due orders. Returns array of { name, result } hashes.
    def run_due!
      results = []
      due.each do |order|
        result = execute_order(order)
        order["last_run_at"] = Time.now.to_i
        results << { name: order["name"], result: }
        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?)
      end
      persist if results.any?
      results
    end

    # Add or update an order by name.
    def upsert(name:, description: "", trigger: "scheduled",
               interval_s: 86_400, command:, enabled: true)
      existing = @orders.find { |o| o["name"] == name.to_s }
      if existing
        existing.merge!(
          "description" => description, "trigger" => trigger.to_s,
          "interval_s"  => interval_s.to_i, "command" => command.to_s,
          "enabled"     => enabled
        )
      else
        @orders << {
          "name"        => name.to_s,
          "description" => description.to_s,
          "trigger"     => trigger.to_s,
          "interval_s"  => interval_s.to_i,
          "command"     => command.to_s,
          "enabled"     => enabled,
          "last_run_at" => 0
        }
      end
      persist
      "standing order '#{name}' saved"
    end

    def enable(name)  = toggle(name, true)
    def disable(name) = toggle(name, false)

    def list
      return "no standing orders defined" if @orders.empty?
      @orders.map do |o|
        status = o["enabled"] ? "on" : "off"
        last   = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
        "#{o['name']} [#{status}] — #{o['description']} (last: #{last})"
      end.join("\n")
    end

    private

    def execute_order(order)
      return Result.err("no pipeline") unless @pipeline

      ctx = { user_message: order["command"].to_s }
      @pipeline.call(Result.ok(**ctx))
    rescue => e
      Result.err(e.message)
    end

    def toggle(name, state)
      o = @orders.find { |x| x["name"] == name.to_s }
      return "no order named '#{name}'" unless o
      o["enabled"] = state
      persist
      "#{name} #{state ? 'enabled' : 'disabled'}"
    end

    def load_orders
      if File.exist?(STORE_PATH)
        YAML.safe_load_file(STORE_PATH) || []
      else
        # Seed with builtins on first run
        BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0) }
      end
    rescue => e
      []
    end

    def persist
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(STORE_PATH))
      File.write(STORE_PATH, YAML.dump(@orders))
    end
  end
end
