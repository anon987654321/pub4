# frozen_string_literal: true

require_relative "command_registry/command"
require_relative "command_registry/help"
require_relative "command_registry/review"
require_relative "command_registry/observe"
require_relative "command_registry/status"
require_relative "command_registry/model"
require_relative "model_benchmark"
require_relative "command_registry/rules"
require_relative "command_registry/host"
require_relative "command_registry/workspace"
require_relative "../review/review_crew"

module Master
  module CLI
    module CommandRegistry
      module_function

      def build_fast(infra:, ai:, root:)
        bus = infra[:bus]
        git = Io::GitOperations.new(File.expand_path("..", root))
        trace = infra[:trace]
        {
          "status" => Command.new do |ctx|
            dispatch_status(root:, fix_loop: nil, bus:, git:, trace:, learnings: infra[:learnings], ctx:)
          end,
          "help" => command(:help_text, nil),
        }
      end

      # Closed public surface: every verb here has a help topic, and every file
      # under command_registry/ holds the dispatchers these verbs reach or the
      # stages Pipeline::Pass calls. Observation and critique stay as methods the
      # pass calls; they are not slash verbs.
      #
      # The surface is closed on purpose. Work is a sentence: TurnRouter reaches
      # the Fold and MediaIntent reaches STUDIO from plain language, and every
      # verb added is one more thing a reader learns before knowing which of them
      # writes. A dispatcher this hash does not return is unreachable, and
      # test_command_registry_dispatch.rb fails on a `*_commands` table it misses.
      def build(infra:, ai:, root:)
        d = command_deps(ai:, root:, infra:)
        undo = infra[:undo]
        review_verbs(d).merge(
          "status" => command(:dispatch_status, d[:root], d[:fix_loop], d[:bus], d[:git], d[:trace], d[:learnings]),
          "device" => command(:dispatch_device, d[:root]),
          "undo" => command(:dispatch_undo, undo),
          "rollback" => command(:dispatch_undo, undo),
          "clear" => command(:dispatch_clear, infra[:session]),
          "commit" => command(:dispatch_commit, ai[:agent], root, review_gate: true),
          "model" => command(:dispatch_model, d[:agent], d[:config], d[:metrics], d[:root]),
          "auth" => command(:dispatch_auth),
          "pair" => command(:dispatch_pair, root),
          "runtime" => command(:dispatch_runtime, d[:root]),
          "doctor" => command(:dispatch_doctor, root),
          "rules" => command(:dispatch_rules, root),
          "law" => command(:dispatch_law),
          "why" => command(:dispatch_why, d[:agent], d[:root]),
          "help" => command(:help_text, nil),
        ).merge(control_commands(ai[:standing], ai[:soul]))
      end

      # Positional, and the order is load-bearing: Command#dependency_kwargs
      # zips these against dispatch_review's keyword names in declaration
      # order, so swarm goes last in both places. /fix takes the same
      # dependencies as /review because it is the same pipeline with the
      # repair turned on -- the one verb that writes.
      def review_verbs(d)
        {
          "review" => command(:dispatch_review, d[:scanner], d[:fix_loop], d[:deliberation], d[:root], d[:bus],
            d[:review_crew], d[:swarm]),
          "fix" => command(:dispatch_fix, d[:scanner], d[:fix_loop], d[:deliberation], d[:root], d[:bus],
            d[:review_crew], d[:swarm]),
        }
      end

      def command_deps(ai:, root:, infra:)
        {
          root:,
          scanner: ai[:scanner],
          fix_loop: ai[:fix_loop],
          deliberation: ai[:deliberation],
          agent: ai[:agent],
          review_crew: Review::ReviewCrew.new(agent: ai[:agent], event_bus: infra[:bus], root:,
                                             code_index: ai[:code_index], reference_graph: ai[:reference_graph]),
          git: ai.fetch(:git) { Io::GitOperations.new(File.expand_path("..", root)) },
          swarm: ai[:swarm],
          bus: infra[:bus],
          config: infra[:config],
          metrics: infra[:metrics],
          trace: infra[:trace],
          learnings: infra[:learnings],
        }
      end

      def dispatch_auth(ctx: nil)
        arg = arg_for(ctx)
        return auth_status_lines if arg.empty? || arg == "status"

        name = arg.delete_prefix("login").strip if arg.start_with?("login")
        return Ground::SubscriptionAuth.login(name) if name && !name.empty?

        return Ground::SubscriptionAuth.login(arg) unless arg.include?(" ")
        "auth  auth status  auth login <claude|chatgpt|grok>"
      end

      def auth_status_lines
        Ground::SubscriptionAuth.status.map { |row| "auth: #{row[:name]} #{auth_state_label(row)}" }.join("\n")
      end

      def auth_state_label(row)
        return "not installed" unless row[:installed]
        return "connected" if row[:authenticated]
        return "not connected" if row[:authentication_known]

        "installed"
      end

      def dispatch_law(ctx: nil)
        case arg_for(ctx)
        when "", "contract" then Law::Contract.render
        when "full" then Law::Contract.render(full: true)
        when "digest" then Law::Contract.digest
        when "protocol" then Law::Contract::PROTOCOL.join("\n")
        else
          "law  law contract  law full  law digest  law protocol"
        end
      end

      def dispatch_device(root, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "status" then Master::Device.status_lines.join("\n")
        when "battery" then Master::Device.battery.to_json
        when "camera" then Master::Device.camera_info.to_json
        when "sensors" then Master::Device.sensors.to_json
        when "audio" then Master::Device.audio_info.to_json
        when "wifi" then Master::Device.wifi_info.to_json
        when "volume" then Master::Device.volume.to_json
        when /\Atorch\s+(on|off)\z/ then Master::Device.torch($1 == "on").to_s
        when /\Aphoto\s+(.+)\z/
          Master::Device.camera_photo($1.strip).to_s
        when /\Arecord\s+(.+?)(?:\s+(\d+))?\z/
          Master::Device.microphone_record($1.strip, limit: $2 && Integer($2)).to_s
        when "record stop" then Master::Device.microphone_stop.to_s
        when /\Alocation(?:\s+(gps|network|passive))?\z/
          Master::Device.location(provider: $1).to_json
        else
          "device  device status  device battery  device camera  device sensors  device audio  device wifi  device volume  device torch [on|off]  device location [gps|network|passive]"
        end
      rescue Master::Device::Error => e
        "device0: unavailable — #{e.message}"
      end

      def dispatch_clear(session, ctx: nil)
        session.clear!
        "context cleared"
      end

      def dispatch_undo(undo, ctx: nil) = undo_line("reverted", undo.undo!)

      def dispatch_runtime(root, ctx: nil)
        runtime = Ground::KnownGood.new(root: root)
        case arg_for(ctx)
        when "", "status"
          record = runtime.current
          record ? "known-good: #{record["commit"]} promoted #{record["promoted_at"]}" : "known-good: none"
        when "promote"
          head, status = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "--short", "HEAD")
          return "runtime promote: git unavailable" unless status.success?

          result = runtime.promote!(commit: head.strip, paths: [])
          result.ok? ? "known-good: promoted #{head.strip}" : result.message
        when "rollback"
          "runtime rollback requires --confirm"
        when "rollback --confirm"
          result = runtime.rollback!
          result.ok? ? result.value!.to_s : result.message
        else
          "runtime  runtime status  runtime promote  runtime rollback"
        end
      end

      def undo_line(verb, result) = result.ok? ? "#{verb}: #{result.value!}" : result.message

      # /orders and /soul. data/state.yml describes standing orders running
      # "via /orders" and data/soul.yml describes amendment as
      # `soul propose -> soul approve`; the amendment path the constitution
      # names has to be reachable from the runtime the constitution governs.
      def control_commands(standing, soul)
        {
          "orders" => command(:dispatch_orders, standing),
          "soul" => command(:dispatch_soul, soul),
        }
      end

      def dispatch_orders(standing, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "list", "" then standing.list
        when /\Aenable (.+)\z/ then standing.enable($1.strip)
        when /\Adisable (.+)\z/ then standing.disable($1.strip)
        when /\Aadd (.+)\z/ then add_order(standing, $1)
        when "run" then run_due_orders(standing)
        when /\Areset (.+)\z/ then standing.reset($1.strip)
        when /\Aconsent (\S+)\z/ then Master::Ground::Tool::Domain.grant($1)
        when /\Arevoke (\S+)\z/ then Master::Ground::Tool::Domain.revoke($1)
        else ORDERS_USAGE
        end
      end

      # key=value pairs, each value running to the next known key, so a verify
      # or a command keeps its spaces and its own `VAR=value` words.
      ORDER_KEYS = { "name" => :name, "cmd" => :command, "domain" => :domain, "wake" => :trigger,
                     "every" => :interval_s, "verify" => :verify, "owner" => :owner }.freeze

      ORDERS_USAGE = "usage: /orders  /orders enable|disable|reset <name>  /orders run\n" \
                     "       /orders consent|revoke <domain>\n" \
                     "       /orders add name=<n> [domain=<d>] [wake=scheduled|heartbeat] [every=<s>] " \
                     "[verify=<argv>] [cmd=<text>]"

      def add_order(standing, text)
        pairs = text.split(/\s+(?=(?:#{ORDER_KEYS.keys.join("|")})=)/).map { |pair| pair.split("=", 2) }
        fields = pairs.filter_map { |key, value| [ORDER_KEYS[key], value.to_s.strip] if ORDER_KEYS[key] }.to_h
        return ORDERS_USAGE unless fields[:name]

        fields[:owner] ||= Fiber[:master_pair_subject].to_s.then { |paired| paired.empty? ? "operator" : paired }
        standing.upsert(**fields)
      end

      def run_due_orders(standing)
        results = standing.run_due!
        return "no orders due" if results.empty?
        results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      end

      def dispatch_soul(soul, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "show" then soul.summary
        when "version", "changelog" then soul.changelog
        when "diff" then soul.diff
        when "approve" then soul.approve
        when "reject" then soul.reject
        when "rollback" then soul.rollback
        when /\Apropose (.+)\z/ then soul.propose($1.strip)
        else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>"
        end
      end

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip
      def expand_or_root(arg, root) = arg.empty? ? root : File.expand_path(arg, root)
      def command(method, *args, **kwargs) = Command.new(self, method, *args, **kwargs)
      alias cmd command
    end
  end
end
