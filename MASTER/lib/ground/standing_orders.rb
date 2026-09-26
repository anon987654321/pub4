# frozen_string_literal: true

require "set"
require "shellwords"

module Master
  module Ground
    # The objective ledger. An order is an objective that outlives the process:
    # it has an owner, an authority domain (Tool::Domain), a wake — a schedule,
    # a bus event, or every heartbeat — the command or callable that makes
    # progress, and a verify command whose exit decides whether it is met. What
    # each run and each check printed is its evidence, kept beside its state in
    # .master/, so a restart resumes the objective rather than forgetting it.
    #
    # One record, not a second: memory holds what MASTER knows, this holds what
    # MASTER is still trying to do (MASTER/AGENTS.md, "No second record beside
    # memory").
    class StandingOrders
      # CRUD + display for the order definitions themselves — separate from
      # StandingOrders' own scheduling/event-dispatch responsibility.
      module OrderManagement
        def upsert(name:, command: nil, **fields)
          existing = @orders.find { |o| o["name"] == name.to_s }
          definition = order_definition(name, command, **fields)
          if existing
            existing.merge!(definition)
          else
            @orders << definition.merge("state" => "pending", "last_run_at" => 0, "runtime" => true)
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
          seen = Array(o["evidence"]).last
          proof = if seen
"  #{seen["kind"]} #{seen["ok"] ? "ok" : "failed"}: #{seen["output"].to_s[0, 60]}"
else
""
end
          "#{o['name']} [#{flag}|#{st}|#{domain_of(o)}] - #{o['description']} (last: #{last})#{err}#{proof}"
        end

        private

        def order_definition(name, command, description: "", trigger: "scheduled", interval_s: DAILY_INTERVAL,
                             enabled: true, domain: Tool::Domain::DEFAULT, owner: "operator", verify: nil)
          {
            "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
            "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
            "domain" => domain.to_s, "owner" => owner.to_s, "verify" => verify&.to_s
          }.compact
        end
      end

      include Master::Io::AtomicWrite
      include OrderManagement
      DAILY_INTERVAL = 86_400
      WEEKLY_INTERVAL = 604_800
      ERROR_TRUNCATE = 200
      DEBOUNCE_S = 10
      VERIFY_TIMEOUT_S = 120
      EVIDENCE_KEEP = 5
      DEFS_PATH = Master.state_path
      STATE_PATH = File.join(Master::ROOT, ".master", "standing_orders_state.yml")
      STATE_KEYS = %w[state last_run_at last_error evidence].freeze
      DEFINITION_KEYS = %w[
        name description trigger interval_s command enabled domain owner verify event filter exclude
      ].freeze
      VALID_STATES = %w[pending running done error verified].freeze
      EVENT_SUBSCRIPTIONS = %w[tool:after].freeze
      # What a wake runs on its own: a schedule is due when its interval has
      # passed, a heartbeat order on every heartbeat tick past its interval.
      WAKES = %w[scheduled heartbeat].freeze

      BUILTIN_ORDERS = [
        { name: "nightly_dreams", description: "Consolidate memories during low-activity periods",
          trigger: "scheduled", interval_s: 86_400, command: "dreams consolidate", enabled: true },
        { name: "weekly_reading", description: "Weekly codebase reading for regressions, writing nothing",
          trigger: "scheduled", interval_s: 604_800, command: "fix --dry-run", enabled: false },
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

      # A verified objective is met and stops waking; an errored one waits for
      # /orders reset.
      def due(owner: nil)
        now = Time.now.to_i
        @orders.select do |o|
          o["enabled"] &&
            (owner.nil? || o["owner"].to_s == owner.to_s) &&
            WAKES.include?(o["trigger"]) &&
            %w[pending done].include?(state_of(o)) &&
            (now - o["last_run_at"].to_i) >= o["interval_s"].to_i
        end
      end

      def run_due!(owner: nil)
        results = due(owner:).map { |order| run_one_order(order) }
        persist if results.any?
        results
      end

      private

      def run_one_order(order)
        order["state"] = "running"
        persist

        result = execute_order(order)
        settle(order, result)
        @bus&.publish("standing_order:ran", name: order["name"], ok: result.ok?, state: order["state"])
        { name: order["name"], result: }
      end

      # The run is evidence either way. A run that worked and has a verify is
      # checked: a passing check meets the objective, a failing one leaves it
      # waking. Only a run that failed is an error.
      def settle(order, result)
        order["last_run_at"] = Time.now.to_i
        witness(order, kind: "run", result:)
        if result.err?
          order["state"] = "error"
          order["last_error"] = result.message.to_s[0, ERROR_TRUNCATE]
          return
        end

        order.delete("last_error")
        met = order["verify"] && witness(order, kind: "verify", result: verify(order)).ok?
        order["state"] = met ? "verified" : "done"
      end

      def witness(order, kind:, result:)
        ok = result.ok?
        said = (ok ? result.value : result.message).to_s
        entry = { "at" => Time.now.to_i, "kind" => kind, "ok" => ok, "output" => said[0, ERROR_TRUNCATE] }
        order["evidence"] = [*Array(order["evidence"]), entry].last(EVIDENCE_KEEP)
        result
      end

      # Command output, not a claim (soul.yml anti_simulation): the exit status
      # of a real process decides, under the same unattended sandbox as a command.
      def verify(order)
        refusal = domain_refusal(order, "exec") || unattended_refusal(order["verify"])
        return refusal if refusal

        argv = Shellwords.split(order["verify"].to_s)
        out, status = Master::Io::Exec.capture2e(*argv, chdir: Master::ROOT, timeout: VERIFY_TIMEOUT_S)
        status.success? ? Result.ok(out.strip) : Result.err(out.strip)
      rescue StandardError => e
        Result.err("verify: #{e.message}")
      end

      def subscribe_events!
        return unless @bus
        EVENT_SUBSCRIPTIONS.each do |event_name|
          @bus.subscribe(event_name) { |ev| dispatch_event(event_name, ev) }
        end
        @bus.subscribe("heartbeat:tick") { run_due! }
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
          settle(order, result)
          persist
        end
        @bus&.publish("standing_order:ran", name:, ok: result.ok?, trigger: "event")
      rescue StandardError => e
        @bus&.publish("standing_order:error", name: order["name"], error: e.message)
      ensure
        @mutex.synchronize { @running.delete(order["name"]) }
      end

      def state_of(order) = VALID_STATES.include?(order["state"]) ? order["state"] : "done"
      def domain_of(order) = order.fetch("domain", Tool::Domain::DEFAULT).to_s

      def execute_order(order, event: nil)
        return execute_callable(order, event:) if order["callable"]
        # An objective with nothing to do between checks: the verify is the work.
        return Result.ok("nothing to run; the verify decides") if order["command"].to_s.empty? && order["verify"]

        refusal = domain_refusal(order, "commands") || unattended_refusal(order["command"])
        return refusal if refusal
        return Master::CLI::TurnRouter.call(message: order["command"].to_s, container: @container) if @container[:commands]

        return @pipeline.call(Result.ok(user_message: order["command"].to_s)) if @pipeline

        Result.err("no router")
      rescue StandardError => e
        Result.err(e.message)
      end

      # Callable orders are code, reviewed as code, and still act in a domain:
      # they get only what that domain reaches.
      def execute_callable(order, event:)
        refusal = domain_refusal(order, "callables")
        return refusal if refusal

        klass = Master::Ground::Orders::Registry.lookup(order["callable"])
        return Result.err("unknown callable: #{order["callable"]}") unless klass

        klass.new(container: Tool::Domain.container(domain_of(order), @container)
                                         .merge(bus: @bus, root: Master::ROOT, event:)).call
      end

      def domain_refusal(order, capability)
        reason = Tool::Domain.refusal(domain_of(order), capability)
        Result.err("standing order refused: #{reason}", category: :policy) if reason
      end

      # An order runs with nobody watching, so a command the sandbox would deny
      # or stop to ask a person about — a hard reset, a push, doas — is refused
      # here rather than routed. Callable orders are code, reviewed as code, and
      # never reach this.
      def unattended_refusal(command)
        decision = Master::Ground::Policy::Sandbox.decide(command.to_s)
        return unless decision.deny? || decision.recognised_ask?

        Result.err("standing order refused: #{command.to_s[0, 80]} (#{decision.reason}; orders run unattended)",
                   category: :policy)
      end

      def toggle(name, enabled)
        order = @orders.find { |x| x["name"] == name.to_s }
        return "no order named '#{name}'" unless order
        order["enabled"] = enabled
        persist
        "#{name} #{enabled ? 'enabled' : 'disabled'}"
      end

      # Declared orders come from data/state.yml; an objective added at runtime
      # carries its definition in the state file, which is what lets it survive
      # a restart without the runtime writing data/.
      def load_orders
        state = read_state
        defs = read_defs
        added = state.reject { |name, _| defs.any? { |order| order["name"] == name } }
                     .filter_map { |_, carry| carry["definition"]&.merge("runtime" => true) }
        (defs + added).each { |order| restore(order, state[order["name"]] || {}) }
      end

      def restore(order, carry)
        order["state"] = carry["state"] || "pending"
        order["last_run_at"] = carry["last_run_at"] || 0
        order["last_error"] = carry["last_error"] if carry["last_error"]
        order["evidence"] = carry["evidence"] if carry["evidence"]
        mark_interrupted(order) if order["state"] == "running"
      end

      # A fresh process runs nothing yet, so a carried "running" is a run the last
      # process died inside. Its outcome is unknown: neither done nor retried, but
      # parked as an error that says so, until the operator resets it.
      def mark_interrupted(order)
        order["state"] = "error"
        order["last_error"] = "interrupted: the process stopped before this run finished"
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
          row = STATE_KEYS.each_with_object({}) { |k, h| h[k] = order[k] if order.key?(k) }
          row["definition"] = order.slice(*DEFINITION_KEYS) if order["runtime"]
          acc[order["name"]] = row
        end
        FileUtils.mkdir_p(File.dirname(STATE_PATH))
        write_atomic(STATE_PATH, state.to_yaml)
      end
    end
  end
end
