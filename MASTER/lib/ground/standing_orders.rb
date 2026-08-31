# frozen_string_literal: true

require "set"

module Master
  module Ground
    class StandingOrders
      # CRUD + display for the order definitions themselves — separate from
      # StandingOrders' own scheduling/event-dispatch responsibility.
      module OrderManagement
        def upsert(name:, description: "", trigger: "scheduled",
                   interval_s: 86_400, command:, enabled: true)
          existing = @orders.find { |o| o["name"] == name.to_s }
          if existing
            existing.merge!(
              "description" => description, "trigger" => trigger.to_s,
              "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled
            )
          else
            @orders << {
              "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
              "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
              "state" => "pending", "last_run_at" => 0
            }
          end
          persist
          "standing order '#{name}' saved"
        end

        def enable(name) = toggle(name, true)
        def disable(name) = toggle(name, false)

        def reset(name)
          order = @orders.find { |x| x["name"] == name.to_s }
          return "no order named '#{name}'" unless order
          order["state"] = "pending"
          order.delete("last_error")
          persist
          "'#{name}' reset -> pending"
        end

        def list
          return "no standing orders defined" if @orders.empty?
          @orders.map { |o| format_order(o) }.join("\n")
        end

        def format_order(o)
          st = state_of(o)
          flag = o["enabled"] ? "on" : "off"
          last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
          err = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
          "#{o['name']} [#{flag}|#{st}] - #{o['description']} (last: #{last})#{err}"
        end
      end
    end
  end
end

module Master
  module Ground
    class StandingOrders
      include AtomicWrite
      include OrderManagement
      DAILY_INTERVAL = 86_400
      WEEKLY_INTERVAL = 604_800
      ERROR_TRUNCATE = 200
      DEBOUNCE_S = 10
      DEFS_PATH = Master.state_path
      STATE_PATH = File.join(Master::ROOT, ".master", "standing_orders_state.yml")
      STATE_KEYS = %w[state last_run_at last_error].freeze
      VALID_STATES = %w[pending running done error].freeze
      EVENT_SUBSCRIPTIONS = %w[tool:after].freeze

      BUILTIN_ORDERS = [
        { name: "nightly_dreams", description: "Consolidate memories during low-activity periods",
          trigger: "scheduled", interval_s: 86_400, command: "dreams consolidate", enabled: true },
        { name: "weekly_scan", description: "Weekly codebase axiom scan for regressions",
          trigger: "scheduled", interval_s: 604_800, command: "scan", enabled: false },
      ].freeze

      def initialize(pipeline: nil, event_bus: nil, container: {})
        @pipeline = pipeline
        @bus = event_bus
        @container = container
        @orders = load_orders
        @mutex = Mutex.new
        @running = Set.new
        subscribe_events!
      end

      def wire_container(container)
        @container = container
      end

      def due
        now = Time.now.to_i
        @orders.select do |o|
          o["enabled"] &&
            o["trigger"] == "scheduled" &&
            %w[pending done].include?(state_of(o)) &&
            (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
        end
      end

      def run_due!
        results = due.map { |order| run_one_order(order) }
        persist if results.any?
        results
      end

      private

      def run_one_order(order)
        order["state"] = "running"
        persist

        result = execute_order(order)
        order["last_run_at"] = Time.now.to_i

        if result.ok?
          order["state"] = "done"
          order.delete("last_error")
        else
          order["state"] = "error"
          order["last_error"] = result.message.to_s[0, ERROR_TRUNCATE]
        end

        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?, state: order["state"])
        { name: order["name"], result: }
      end

      def subscribe_events!
        return unless @bus
        EVENT_SUBSCRIPTIONS.each do |event_name|
          @bus.subscribe(event_name) { |ev| dispatch_event(event_name, ev) }
        end
      end

      def dispatch_event(event_name, payload)
        @orders.each do |order|
          next unless event_match?(order, event_name, payload)
          next if debounced?(order)
          next unless @mutex.synchronize { @running.add?(order["name"]) }
          Thread.new { run_event_order(order, payload) }.tap { |t| t.abort_on_exception = false }
        end
      end

      def event_match?(order, event_name, payload)
        return false unless order["enabled"]
        return false unless order["trigger"] == "event"
        return false unless order["event"].to_s == event_name
        filter_match?(order, payload) && !exclude_match?(order, payload)
      end

      def filter_match?(order, payload)
        pattern = order["filter"].to_s
        return true if pattern.empty?
        payload_strings(payload).any? { |s| Regexp.new(pattern).match?(s) }
      end

      def exclude_match?(order, payload)
        pattern = order["exclude"].to_s
        return false if pattern.empty?
        payload_strings(payload).any? { |s| Regexp.new(pattern).match?(s) }
      end

      def payload_strings(payload)
        [payload[:tool], payload[:path], payload[:full]].compact.map(&:to_s)
      end

      def debounced?(order)
        last = order["last_run_at"].to_i
        last.positive? && (Time.now.to_i - last) < DEBOUNCE_S
      end

      def run_event_order(order, payload = nil)
        name = order["name"]
        result = execute_order(order, event: payload)
        @mutex.synchronize do
          order["last_run_at"] = Time.now.to_i
          if result.ok?
            order["state"] = "done"
            order.delete("last_error")
          else
            order["state"] = "error"
            order["last_error"] = result.message.to_s[0, ERROR_TRUNCATE]
          end
          persist
        end
        @bus&.publish("standing_order:ran", name:, ok: result.ok?, trigger: "event")
      rescue StandardError => e
        @bus&.publish("standing_order:error", name: order["name"], error: e.message)
      ensure
        @mutex.synchronize { @running.delete(order["name"]) }
      end

      def state_of(order) = VALID_STATES.include?(order["state"]) ? order["state"] : "done"

      def execute_order(order, event: nil)
        if (callable_key = order["callable"])
          klass = Master::Ground::Orders::Registry.lookup(callable_key)
          return Result.err("unknown callable: #{callable_key}") unless klass
          return klass.new(container: @container.merge(bus: @bus, root: Master::ROOT, event:)).call
        end
        return Master::CLI::TurnRouter.call(message: order["command"].to_s, container: @container) if @container[:commands]

        return @pipeline.call(Result.ok(user_message: order["command"].to_s)) if @pipeline

        Result.err("no router")
      rescue StandardError => e
        Result.err(e.message)
      end

      def toggle(name, enabled)
        order = @orders.find { |x| x["name"] == name.to_s }
        return "no order named '#{name}'" unless order
        order["enabled"] = enabled
        persist
        "#{name} #{enabled ? 'enabled' : 'disabled'}"
      end

      def load_orders
        defs = read_defs
        state = read_state
        defs.each do |order|
          carry = state[order["name"]] || {}
          order["state"] = carry["state"] || "pending"
          order["last_run_at"] = carry["last_run_at"] || 0
          order["last_error"] = carry["last_error"] if carry["last_error"]
        end
        defs
      end

      def read_defs
        if File.exist?(DEFS_PATH)
          raw = Master.load_yaml(DEFS_PATH)
          return builtin_orders unless raw.is_a?(Array)
          raw.select { |o| o.is_a?(Hash) }
        else
          builtin_orders
        end
      rescue Psych::Exception, Errno::ENOENT, TypeError, NoMethodError => e
        @bus&.publish("standing_orders:load_error", error: e.message)
        builtin_orders
      end

      def read_state
        return {} unless File.exist?(STATE_PATH)
        raw = Master.load_yaml(STATE_PATH)
        raw.is_a?(Hash) ? raw : {}
      rescue Psych::Exception, Errno::ENOENT, TypeError => e
        Master::Ground::Swallow.log(e, context: "StandingOrders.read_state")
        {}
      end

      def builtin_orders
        BUILTIN_ORDERS.map { |o| o.transform_keys(&:to_s).merge("last_run_at" => 0, "state" => "pending") }
      end

      def persist
        return unless @orders.is_a?(Array)
        state = @orders.each_with_object({}) do |order, acc|
          acc[order["name"]] = STATE_KEYS.each_with_object({}) { |k, h| h[k] = order[k] if order.key?(k) }
        end
        FileUtils.mkdir_p(File.dirname(STATE_PATH))
        write_atomic(STATE_PATH, state.to_yaml)
      end
    end
  end
end
