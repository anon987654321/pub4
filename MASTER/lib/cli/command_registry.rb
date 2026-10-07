# frozen_string_literal: true

require_relative "../snapshot"
require_relative "../../tools/snapshot"
require "shellwords"
require_relative "../io/media_intent"

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
require_relative "command_registry/convergence"
require_relative "../plugin"

module Master
  module CLI
    module CommandRegistry
      module_function

      # Closed public surface: every verb here has a help topic. Review and
      # critique remain compatibility adapters; /fix is the canonical lifecycle
      # and the only public verb that may write.
      #
      # The surface is closed on purpose. Work is a sentence: TurnRouter reaches
      # the Fold and MediaIntent reaches MASTER/tools from plain language, and every
      # verb added is one more thing a reader learns before knowing which of them
      # writes. A dispatcher this hash does not return is unreachable, and
      # test_command_registry_dispatch.rb fails on a `*_commands` table it misses.
      def build(infra:, ai:, root:)
        d = command_deps(ai:, root:, infra:)
        review_verbs(d).merge(session_verbs(infra[:session], infra[:undo])).merge(
          "status" => command(:dispatch_status, d[:root], d[:fix_loop], d[:bus], d[:git], d[:trace], d[:learnings]),
          "commit" => command(:dispatch_commit, ai[:agent], root, review_gate: true),
          "deploy" => command(:dispatch_deploy, root, review_gate: true),
          "model" => command(:dispatch_model, d[:agent], d[:config], d[:metrics], d[:root]),
          "plugin" => command(:dispatch_plugin),
          "play" => command(:dispatch_play, d[:root]),
          "android" => command(:dispatch_android, root),
          "ios" => command(:dispatch_ios, root),
          "wake" => command(:dispatch_wake, root),
          "doctor" => command(:dispatch_doctor, root),
          "voice" => Command.new { |ctx| dispatch_voice(ctx:) },
          "rules" => command(:dispatch_rules, root),
          "snapshot" => command(:dispatch_snapshot, d[:root]),
          "why" => command(:dispatch_why, d[:agent], d[:root], d[:memory]),
          "wishlist" => command(:dispatch_wishlist, d[:root]),
          "size" => command(:dispatch_size, d[:root]),
          "explain" => command(:dispatch_explain, d[:root]),
          "prove" => command(:dispatch_prove, d[:root]),
          "events" => command(:dispatch_events, d[:root]),
          "face" => Command.new { |_ctx| dispatch_face },
          "help" => command(:help_text, nil),
        ).merge(control_commands(ai[:standing], ai[:soul]))
      end

      # The verbs that read or rewind the conversation: which one is active,
      # its forks, and what undo can take back.
      def session_verbs(session, undo)
        {
          "undo" => command(:dispatch_undo, undo),
          "clear" => command(:dispatch_clear, session),
          "session" => command(:dispatch_session, session),
        }
      end

      # One verb for the conversations, where there were four names for three
      # acts: bare lists them, `continue` (or `resume`) switches, `fork` branches.
      def dispatch_session(session, ctx: nil)
        word, rest = subcommand(ctx)
        case word
        when "", "list" then dispatch_sessions(session)
        when "continue", "resume" then dispatch_continue(session, ctx: rest)
        when "fork" then dispatch_fork(session, ctx: rest)
        else "session  session continue <id>  session fork [id]"
        end
      end

      # The first word of a verb's arguments, and a ctx carrying the rest, so a
      # host verb hands a folded one exactly what it was handed before.
      def subcommand(ctx)
        word, rest = arg_for(ctx).split(/\s+/, 2)
        [word.to_s.downcase, { args: rest.to_s }]
      end

      # Positional, and the order is load-bearing: Command#dependency_kwargs
      # zips these against dispatch_review's keyword names in declaration
      # order, so swarm goes last in both places. /fix takes the same
      # dependencies as /review because it is the same pipeline with the
      # repair turned on -- the one verb that writes.
      def review_verbs(d)
        # These dispatchers are keyword-only. Build the calls as keyword calls
        # here rather than relying on positional-to-keyword recovery in Command;
        # Ruby 3+ deliberately keeps those argument kinds separate.
        deps = {
          scanner: d[:scanner], fix_loop: d[:fix_loop], deliberation: d[:deliberation],
          root: d[:root], bus: d[:bus], swarm: d[:swarm]
        }
        {
          "review" => Command.new { |ctx| dispatch_review(**deps, ctx:) },
          "critique" => Command.new { |ctx| dispatch_critique(**deps, ctx:) },
          "fix" => Command.new { |ctx| dispatch_fix(**deps, ctx:) },
        }
      end

      def command_deps(ai:, root:, infra:)
        {
          root:,
          scanner: ai[:scanner],
          fix_loop: ai[:fix_loop],
          deliberation: ai[:deliberation],
          agent: ai[:agent],
          git: ai.fetch(:git) { Io::GitOperations.new(File.expand_path("..", root)) },
          swarm: ai[:swarm],
          bus: infra[:bus],
          config: infra[:config],
          metrics: infra[:metrics],
          trace: infra[:trace],
          learnings: infra[:learnings],
          memory: infra[:memory],
        }
      end

      def dispatch_plugin(ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "list"
          Master::Plugin.list.map { |manifest| "#{manifest.id}: #{manifest.description}" }.join("\n")
        when /\Ainfo\s+([a-z][a-z0-9_]*)\z/
          manifest = Master::Plugin.info($1)
          "#{manifest.id} #{manifest.version} — #{manifest.description}"
        when /\Arun\s+([a-z][a-z0-9_]*)\s+([a-z][a-z0-9_]*)\s*(.*)\z/
          args = $3.to_s.strip
          payload = args.empty? ? {} : JSON.parse(args)
          raise ArgumentError, "plugin arguments must be a JSON object" unless payload.is_a?(Hash)

          Master::Plugin.run($1, action: $2, **payload.transform_keys(&:to_sym)).to_json
        else
          "plugin  plugin list  plugin info <id>  plugin run <id> <action> <json>"
        end
      rescue JSON::ParserError => e
        "plugin0: invalid JSON — #{e.message}"
      rescue Master::Plugin::Error, ArgumentError => e
        "plugin0: #{e.message}"
      end

      # /play is the MASTER front door to Dilla. With no argument it is exactly
      # the same showcase as bare `ruby dilla.rb`; an artist argument keeps the
      # named source lane. Nothing falls through to the shell or a web-search guess.
      def dispatch_play(root, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        result = Master::Io::MediaIntent.play_live_music(arg, root:)
        result.ok? ? result.value![:rendered].to_s : result.message.to_s
      end

      def dispatch_auth(ctx: nil)
        arg = arg_for(ctx)
        return auth_status_lines if arg.empty? || arg == "status"

        name = arg.delete_prefix("login").strip if arg.start_with?("login")
        return Ground::SubscriptionAuth.login(name) if name && !name.empty?

        return Ground::SubscriptionAuth.login(arg) unless arg.include?(" ")
        "model auth  model auth status  model auth login <claude|chatgpt|grok>"
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
        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?

        arg = arg_for(ctx)
        case arg
        when "", "contract" then Law::Contract.render
        when "full" then Law::Contract.render(full: true)
        when "digest" then Law::Contract.digest
        when "protocol" then Law::Contract::PROTOCOL.join("\n")
        when "handshake" then JSON.generate(Master::Ground::LawHandshake.new.export)
        else
          "soul law  soul law contract|full|digest|protocol|handshake"
        end
      end

      def dispatch_snapshot(_root, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /snapshot [no arguments]" unless arg.empty?

        paths = ::Operator::Snapshot::TREES.flat_map { |tree| Array(::Operator::Snapshot.write(tree)) }
        paths.map do |path|
          relative = path.delete_prefix("#{Master::REPO_ROOT}/")
          bytes = File.size(path)
          "snapshot0: wrote root/#{relative} (#{bytes} bytes; max #{::Operator::Snapshot::MAX_BYTES})"
        end.join("\n")
      rescue StandardError => e
        "snapshot0: failed — #{e.class}: #{e.message}"
      end

      # Open the full-screen terminal face without inventing a second model route.
      def dispatch_face(_ctx = nil)
        return "face0: needs a terminal" unless $stdin.tty? && $stdout.tty?

        container = Fiber[:master_cli_container]
        return "face0: no session" unless container

        turn = ->(text) do
          streamed = +""
          result = TurnRouter.call(message: text, container:, on_turn: ->(line) { streamed << line << "\n" })
          return result if streamed.strip.empty? || result.err?

          streamed
        end
        Face::Window.new(
          turn:,
          event_bus: container[:bus],
          input: $stdin,
          output: $stdout,
        ).run
      rescue StandardError => e
        "face0: failed — #{e.class}: #{e.message}"
      end

      def dispatch_device(_root, ctx: nil)
        device_command(arg_for(ctx))
      rescue Master::Device::Error => e
        "device0: unavailable — #{e.message}"
      end

      def dispatch_voice(ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "", "status"
          player = Voice::Playback.player
          enabled = Voice::Playback.enabled?
          engine = Voice::Speech.synthesis_mode
          last = Voice::Transcendent.last_pick
          detail = if last
            "last=#{last[:engine] || "none"} voice=#{last[:voice] || "none"} primary=#{last[:primary] || "none"}"
          else
            "last=none"
          end
          error = Voice::Speech.last_error
          "#{[
            "voice0 at mainbus0: #{enabled ? "on" : "off"}",
            "player=#{player ? player.first : "none"} engine=#{engine}",
            detail,
            ("error=#{error}" if error && !error.empty?)
          ].compact.join("\n")}"
        when "test"
          ok = Voice::Playback.speak_now("MASTER voice test.")
          player = Voice::Playback.player
          if ok
            "voice0 at mainbus0: test passed, player #{player ? player.first : "none"}"
          else
            "voice0 at mainbus0: test failed, see voice/tts diagnostics"
          end
        else
          "voice  voice status  voice test"
        end
      rescue StandardError => e
        "voice0 at mainbus0: failed, #{e.class}: #{e.message}"
      end

      def device_command(arg)
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
          "doctor device  status|battery|camera|sensors|audio|wifi|volume|torch [on|off]|location [gps|network|passive]"
        end
      end

      def dispatch_clear(session, ctx: nil)
        session.clear!
        "context cleared"
      end

      def dispatch_sessions(session, ctx: nil)
        current = session.active_key
        keys = session.conversation_keys
        return "sessions0: none" if keys.empty?
        keys.map { |key| key == current ? "* #{key}" : "  #{key}" }.join("\n")
      end

      def dispatch_continue(session, ctx: nil)
        key = arg_for(ctx)
        key = session.active_key if key.empty?
        session.switch!(key)
        "session0: continued #{key}"
      rescue ArgumentError => e
        "session0: #{e.message}"
      end

      def dispatch_fork(session, ctx: nil)
        target = arg_for(ctx)
        target = nil if target.empty?
        key = session.fork!(target_key: target)
        session.switch!(key)
        "session0: forked #{key}"
      rescue ArgumentError => e
        "session0: #{e.message}"
      end

      def dispatch_undo(undo, ctx: nil) = undo_line("reverted", undo.undo!)

      def dispatch_mission(root, ctx: nil)
        record = Master::Fix::Mission.current(root:)
        arg = arg_for(ctx)
        return "mission0: none" unless record

        case arg
        when "", "status"
          [
            "mission: #{record["id"]}",
            "state: #{record["state"]}",
            "stage: #{record["stage"]}",
            "model: #{record["model"]}",
            "effort: #{record["effort"]}",
            "operator_mode: #{record.dig("operator", "mode") || "repair"}",
            "operator_risk: #{record.dig("operator", "risk") || "unknown"}",
            "model_tier: #{Master::Operator::Mode.spec(record.dig("operator", "mode") || "repair")[:model_tier]}",
            "council_required: #{Master::Operator::Mode.spec(record.dig("operator", "mode") || "repair")[:council]}",
            "evidence_contract: #{Master::Operator::Mode.spec(record.dig("operator", "mode") || "repair")[:evidence]}",
            "goal: #{record["goal"]}",
            "attempt: #{record["attempt_count"]}",
            "retries: #{record["retry_count"]}",
            "next_wake: #{record["next_wake_at"] || "now"}",
            "wake_reason: #{record["wake_reason"] || "none"}",
            "lease: #{record["lease_owner"] || "none"} until #{record["lease_until"] || "none"}",
          ].join("\n")
        else
          "status mission"
        end
      rescue StandardError => e
        "mission0: #{e.class}: #{e.message}"
      end

      def dispatch_runtime(root, ctx: nil)
        runtime = Ground::KnownGood.new(root:)
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
          "status runtime  status runtime promote  status runtime rollback --confirm"
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

        fields[:owner] ||= begin
          paired = Fiber[:master_pair_subject].to_s
          paired = Master::Device::Agent.owner_subject(root: Master::ROOT) if paired.empty? && defined?(Master::Device::Agent)
          paired.empty? ? "operator" : paired
        end
        standing.upsert(**fields)
      end

      def run_due_orders(standing)
        results = standing.run_due!
        return "no orders due" if results.empty?
        results.map { |r| "#{r[:name]}: #{r[:result].ok? ? "ok" : r[:result].message}" }.join("\n")
      end

      # /soul law is the executable law's portable contract: the constitution
      # read as what an external agent must present.
      def dispatch_soul(soul, ctx: nil)
        arg = arg_for(ctx)
        word, rest = subcommand(ctx)
        return dispatch_law(ctx: rest) if word == "law"

        case arg
        when "", "show" then soul.summary
        when "version", "changelog" then soul.changelog
        when "diff" then soul.diff
        when "approve" then soul.approve
        when "reject" then soul.reject
        when "rollback" then soul.rollback
        when /\Apropose (.+)\z/ then soul.propose($1.strip)
        else "soul  soul version  soul diff  soul approve  soul reject  soul rollback  soul propose <rationale>  soul law"
        end
      end

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip
      def expand_or_root(arg, root) = arg.empty? ? root : File.expand_path(arg, root)
      def command(method, *args, **kwargs) = Command.new(self, method, *args, **kwargs)
      alias cmd command
    end
  end
end