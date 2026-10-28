# frozen_string_literal: true

require "stringio"
require_relative "../snapshot"
require_relative "../../tools/snapshot"
require "shellwords"
require_relative "../io/media_intent"
require_relative "../voice/dialogue_rubric"

require_relative "command_registry/command"
require_relative "command_registry/help"
require_relative "command_registry/review"
require_relative "command_registry/observe"
require_relative "command_registry/status"
require_relative "command_registry/model"
require_relative "model_benchmark"
require_relative "command_registry/laws"
require_relative "command_registry/host"
require_relative "command_registry/workspace"
require_relative "command_registry/convergence"
require_relative "../plugin"

module Master
  module CLI
    module CommandRegistry
      module_function

      # Closed public surface: every verb here has a help topic. Review and
      # critique remain compatibility adapters; /fix is the only verb that writes repository code.
      # /preferences changes only the paired subject’s consent-gated local settings.
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
          "commit" => command(:dispatch_commit, ai[:agent], root, review_check: true),
          "deploy" => command(:dispatch_deploy, root, review_check: true),
          "model" => command(:dispatch_model, d[:agent], d[:config], d[:metrics], d[:root]),
          "plugin" => command(:dispatch_plugin),
          "play" => command(:dispatch_play, d[:root]),
          "mov" => command(:dispatch_mov, d[:root]),
          "support" => command(:dispatch_support, d[:agent], d[:root]),
          "screen" => command(:dispatch_screen, root),
          "android" => command(:dispatch_android, root),
          "ios" => command(:dispatch_ios, root),
          "wake" => command(:dispatch_wake, root),
          "privacy" => command(:dispatch_privacy, root),
          "pair" => command(:dispatch_pair, root),
          "preferences" => command(:dispatch_preferences, root),
          "agenda" => command(:dispatch_agenda, root),
          "task" => command(:dispatch_task, root),
          "skill" => command(:dispatch_skill, root),
          "capabilities" => command(:dispatch_capabilities, root),
          "doctor" => command(:dispatch_doctor, root),
          "voice" => Command.new { |ctx| dispatch_voice(ctx:) },
          "narrate" => Command.new { |ctx| dispatch_narrate(ctx:) },
          "bard" => Command.new { |context| dispatch_bard(context:) },
          "reload" => Command.new { |_context| dispatch_reload },
          "incident" => Command.new { |context| dispatch_incident(context:) },
          "laws" => command(:dispatch_laws, root),
          "snapshot" => command(:dispatch_snapshot, d[:root]),
          "why" => command(:dispatch_why, d[:agent], d[:root], d[:memory]),
          "wishlist" => command(:dispatch_wishlist, d[:root]),
          "size" => command(:dispatch_size, d[:root]),
          "explain" => command(:dispatch_explain, d[:root]),
          "prove" => command(:dispatch_prove, d[:root]),
          "events" => command(:dispatch_events, d[:root]),
          "face" => Command.new { |ctx| dispatch_face(ctx) },
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

      # Personal support is automatically routed by the turn prompt. This
      # explicit command runs only the bounded synthetic benchmark; it never
      # consumes a real conversation or silently starts paid model calls.
      def dispatch_support(agent, root, ctx: nil)
        args = Shellwords.split(arg_for(ctx))
        action = args.shift.to_s.downcase
        return help_text("support") if action.empty? || action == "help"
        return "support0 at master0: usage: /support benchmark --confirm [response-model] [judge-model]" unless action == "benchmark"

        unless args.delete("--confirm")
          return "support0 at master0: BLOCKED cost check; this runs up to eight synthetic cases and sixteen model calls. Repeat with --confirm."
        end
        return "support0 at master0: usage: /support benchmark --confirm [response-model] [judge-model]" if args.size > 2
        return "support0 at master0: BLOCKED; no active model agent" unless agent

        response_model, judge_model = args
        report = Master::Voice::DialogueRubric.run_support_benchmark(
          agent:, response_model:, judge_model:, max_cases: 8, root:,
        )
        summary = report.fetch(:summary, {})
        counts = %i[pass needs_review fail inconclusive failed blocked].map do |key|
          "#{key}=#{summary.fetch(key, 0)}"
        end.join(" ")
        lines = [
          "support0 at master0: #{report.fetch(:status, :inconclusive)} cases=#{report.fetch(:case_count, 0)} #{counts}",
          "support0 at master0: model_identifiers_differ=#{report.fetch(:distinct_model_identifiers, false) ? "yes" : "no"} independence=not_proven human_review=required",
        ]
        Array(report[:cases]).each do |item|
          grade = item.fetch(:grade, {})
          scores = grade.fetch(:scores, {})
          score_text = %w[practicality safety calibration].filter_map do |name|
            score = scores[name]
            "#{name}=#{score}" unless score.nil?
          end.join(" ")
          answer_excerpt = item.fetch(:response, "").to_s.gsub(/\s+/, " ").strip[0, 180]
          outcome = grade.fetch(:overall, item.fetch(:status, :unknown))
          lines << "support0: #{item.fetch(:scenario_id)} #{outcome}#{score_text.empty? ? "" : " #{score_text}"}#{answer_excerpt.empty? ? "" : " — #{answer_excerpt}"}"
        end
        lines << "support0 at master0: synthetic screening only; not proof of clinical safety or efficacy."
        lines.join("\n")
      rescue ArgumentError => e
        "support0 at master0: invalid arguments — #{e.message}"
      rescue StandardError => e
        "support0 at master0: FAILED #{e.class}"
      end

      # /play is the MASTER front door to Dilla. With no argument it renders a
      # random progression under a random drum pattern and plays the wav; a name
      # picks the progression or the pattern. Nothing falls through to the shell or
      # a web-search guess.
      def dispatch_play(root, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        result = Master::Io::MediaIntent.play_live_music(arg, root:)
        result.ok? ? result.value![:rendered].to_s : result.message.to_s
      end

      # /mov — find and download films and series from the free, legal
      # collections. Bare /mov discovers recent additions; /mov <words> searches
      # titles; "new" and "a bunch" are read the way a person says them. The
      # downloads land in ~/Downloads, so the repo root is not a parameter the
      # tool needs.
      def dispatch_mov(_root, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        result = Master::Io::Mov.dispatch(arg)
        result.ok? ? result.value![:output].to_s : result.message.to_s
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
        require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

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

      # The full source of each governed tree as one untruncated exact file, verified against the
      # tracked files; bin/operator snapshot takes the other options (--code, --part-bytes, --verify).
      def dispatch_snapshot(_root, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /snapshot [no arguments]  (one exact file per tree; bin/operator snapshot has --code, --part-bytes, --verify)" unless arg.empty?

        log = StringIO.new
        paths = ::Operator::Snapshot::TREES.flat_map { |tree| Array(::Operator::Snapshot.write(tree, full: true, io: log)) }
        wrote = paths.map do |path|
          relative = path.delete_prefix("#{Master::REPO_ROOT}/")
          bytes = File.size(path)
          "snapshot0: wrote root/#{relative} (#{bytes} bytes, ~#{bytes / 4000}K tokens; full source)"
        end
        (wrote + log.string.lines.grep(/verified/).map(&:chomp)).join("\n")
      rescue StandardError => e
        "snapshot0: failed — #{e.class}: #{e.message}"
      end

      # Open the full-screen terminal face without inventing a second model route.
      # `/face size auto|small|large|WxH` chooses how big the face is drawn and
      # opens it; the choice holds for the session. WxH is columns by rows.
      def dispatch_face(ctx = nil, prompt: nil)
        chosen = face_size(arg_for(ctx))
        return chosen if chosen.is_a?(String) && chosen.start_with?("face0:")

        return "face0: needs a terminal" unless $stdin.tty? && $stdout.tty?

        container = Fiber[:master_cli_container]
        return "face0: no session" unless container

        turn = ->(text) do
          return face_shell_only_notice if face_shell_only?(text)

          streamed = +""
          result = TurnRouter.call(message: text, container:, on_turn: ->(line) { streamed << line << "\n" })
          return result if streamed.strip.empty? || result.err?

          streamed
        end
        prompt ||= Fiber[:master_cli_prompt]
        prompt ||= lambda do
          renderer = container[:renderer]
          session = container[:session]
          agent = container[:agent]
          if renderer.respond_to?(:prompt_line) && session
            _state, value = renderer.prompt_line(
              agent&.model, session.phase,
              tokens: session.token_est, cost: session.cost
            )
            value
          else
            Master::Face::Contract.shell_prompt(path: Dir.pwd, root: Master::ROOT)
          end
        end
        terminal = File.open("/dev/tty", "r+")
        Face::Window.new(
          turn:,
          event_bus: container[:bus],
          input: terminal,
          output: terminal,
          prompt:,
        ).run
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.face")
        "face0: failed — #{e.class}: #{e.message}"
      ensure
        terminal&.close
      end

      # A command that runs for minutes would leave the face looking stuck, so it is run from the shell.
      def face_shell_only?(text)
        word = text.to_s.strip.split.first.to_s.downcase
        Array(Master.patterns_config.fetch("cli", {})["face_shell_only"]).include?(word)
      end

      def face_shell_only_notice = "That runs for minutes. Ctrl-D leaves the face; run it in the shell."

      def face_size(arg)
        words = arg.to_s.split
        return unless words.first == "size"

        mode = Face::Sizing.parse(words[1..].join)
        return "face0: size is auto, small, large or WxH (columns by rows); now #{Face::Sizing.mode}" unless mode

        Face::Sizing.mode = mode
        nil
      end

      def dispatch_device(_root, ctx: nil)
        device_command(arg_for(ctx))
      rescue Master::Device::Error => e
        "device0: unavailable — #{e.message}"
      end

      def dispatch_voice(ctx: nil)
        arg = arg_for(ctx).downcase
        case arg
        when "", "status"
          voice_status
        when "on"
          ENV["MASTER_CLI_SPEAK"] = "1"
          if Voice::Playback.enabled?
            "voice0 at mainbus0: on, CLI speech enabled for this session"
          else
            "voice0 at mainbus0: requested on, but blocked by MASTER_SKIP_TTS, CI, or a non-interactive terminal"
          end
        when "off"
          ENV["MASTER_CLI_SPEAK"] = "0"
          Voice::Playback.interrupt!("voice off")
          "voice0 at mainbus0: off, CLI replies remain text"
        when "natural", "normal", "classic", "fast"
          ENV["MASTER_TTS_MODE"] = "classic"
          ENV.delete("MASTER_TTS_PROFILE")
          Voice::Policy.reload!
          "voice0 at mainbus0: natural speech selected; clean voice, normal prosody, fast streaming"
        when "expressive", "transcendent"
          ENV["MASTER_TTS_MODE"] = "transcendent"
          "voice0 at mainbus0: expressive speech selected; heavyweight engines and phrase performance enabled"
        when "dilla"
          ENV["MASTER_TTS_MODE"] = "classic"
          ENV["MASTER_TTS_PROFILE"] = "dilla"
          Voice::Policy.reload!
          "voice0 at mainbus0: Dilla profile selected; classic streaming speech with the effects rack and room"
        when "timing", "diagnostics"
          timings = Voice::Speech.last_timings
          return "voice0 at mainbus0: no timing recorded yet; use /voice test or speak normally" if timings.empty?

          details = timings.sort_by { |stage, _| stage }.map do |stage, values|
            "#{stage}=#{values.fetch(:elapsed_ms)}ms"
          end
          "voice0 timing: #{details.join(' ')}"
        when "test"
          # This explicit diagnostic may speak once even while ordinary CLI
          # replies are off. Restore the user's session switch immediately after
          # the synchronous test; it must not silently enable all future replies.
          original_speak = ENV.fetch("MASTER_CLI_SPEAK", nil)
          begin
            ENV["MASTER_CLI_SPEAK"] = "1"
            ok = Voice::Playback.speak_now("MASTER voice test.")
            player = Voice::Playback.player
            if ok
              "voice0 at mainbus0: test passed, player #{player ? player.first : "none"}"
            else
              "voice0 at mainbus0: test failed, see /voice status for the last error"
            end
          ensure
            original_speak ? ENV["MASTER_CLI_SPEAK"] = original_speak : ENV.delete("MASTER_CLI_SPEAK")
          end
        else
          "voice  voice on  voice off  voice natural  voice expressive  voice dilla  voice status  voice timing  voice test"
        end
      rescue StandardError => e
        "voice0 at mainbus0: failed, #{e.class}: #{e.message}"
      end

      def voice_status
        player = Voice::Playback.player
        enabled = Voice::Playback.enabled?
        engine = Voice::Speech.synthesis_mode
        policy = Voice::Policy
        profile = policy.profile_name.empty? ? "natural" : policy.profile_name
        last = Voice::Transcendent.last_pick
        detail = if last
          "last=#{last[:engine] || "none"} voice=#{last[:voice] || "none"} primary=#{last[:primary] || "none"}"
        else
          "last=none"
        end
        error = Voice::Speech.last_error
        timings = Voice::Speech.last_timings
        timing = timings.empty? ? "timing=not-recorded" : "timing=#{timings.map { |stage, values| "#{stage}:#{values.fetch(:elapsed_ms)}ms" }.join(",")}"
        [
          "voice0 at mainbus0: #{enabled ? "on" : "off"}",
          "player=#{player ? player.first : "none"} engine=#{engine} profile=#{profile} rate=#{policy.default_rate} pitch=#{policy.default_pitch}",
          detail,
          timing,
          ("error=#{error}" if error && !error.empty?),
        ].compact.join("\n")
      end

      def dispatch_narrate(ctx: nil)
        narrator = Voice::Narrator.instance
        case arg_for(ctx).downcase
        when "on"
          Voice::Narrator.instance(:bard).disable!
          narrator.enable!
          "narr0 at voice0: on, MASTER tells what it does as one running story, plainly"
        when "off"
          Voice::Narrator.instance(:bard).disable!
          narrator.disable!
          Voice::Playback.interrupt!("narration off")
          "narr0 at voice0: off, plain one-line speech"
        when "", "status"
          narration_status(narrator.status)
        else
          "narrate  narrate on  narrate off  narrate status"
        end
      rescue StandardError => e
        "narr0 at voice0: failed, #{e.class}: #{e.message}"
      end

      INCIDENT_USAGE = "incident  /incident add <what happened>  /incident list  /incident summary"

      # A private dated log kept on this machine: /incident add <text>, list, summary. See CLI::IncidentLog.
      def dispatch_incident(context: nil)
        verb, text = arg_for(context).split(" ", 2)
        handlers = { "add" => -> { incident_added(text) }, "list" => -> { incident_notes },
                     "summary" => -> { IncidentLog.summary } }
        handler = handlers[verb || "summary"]
        handler ? handler.call : INCIDENT_USAGE
      end

      def incident_notes = IncidentLog.list.then { |list| list.empty? ? IncidentLog.summary : list }

      def incident_added(text)
        entry = IncidentLog.add(text)
        return "incident0: nothing to keep; say what happened" unless entry

        "incident0: kept #{entry["at"][0, 16].tr("T", " ")}, on this machine only"
      end

      # Restart this session in place so edits to lib/ and data/ take effect. The conversation is saved,
      # speech stops first, and the process lock is dropped so the fresh bin/master takes it.
      def dispatch_reload
        Trace::Dmesg.status("master0", "reloading")
        Voice::Playback.interrupt!("reload")

        $stdin.cooked! if $stdin.tty?
        exec({ "MASTER_PROCESS_LOCK_FD" => nil }, File.join(Master::ROOT, "bin", "master"), *ARGV)
      rescue SystemCallError => e
        "reload failed, #{e.class}: #{e.message}"
      end

      # The lyrical teller of the story, on by default. On makes it the one voice that speaks; off
      # hands the story back to the plain narrator.
      def dispatch_bard(context: nil)
        bard = Voice::Narrator.instance(:bard)

        case arg_for(context).downcase
        when "on", "off" then bard_switch(bard, enable: arg_for(context).casecmp?("on"))
        when "", "status" then narration_status(bard.status).sub("narr0", "bard0")
        else "bard  bard on  bard off  bard status"
        end
      rescue StandardError => e
        "bard0 at voice0: failed, #{e.class}: #{e.message}"
      end

      def bard_switch(bard, enable:)
        if enable
          Voice::Narrator.instance.disable!
          bard.enable!
          return "bard0 at voice0: on, MASTER sings what it does as one continuous song"
        end

        bard.disable!
        Voice::Narrator.instance.enable!
        Voice::Playback.interrupt!("bard off")
        "bard0 at voice0: off, the plain narrator tells the story"
      end

      def narration_status(state)
        [
          "narr0 at voice0: #{state[:enabled] ? "on" : "off"}",
          "beats=#{state[:beats]} told=#{state[:told]} pending=#{state[:pending]} sentences/min=#{state[:sentences_last_minute]}",
          "model=#{state[:model] ? "live" : "template"} calls=#{state[:calls]} cost=$#{state[:cost_usd]} of $#{state[:max_cost_usd]}",
        ].join("\n")
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

      # The Fold's mission lives under MASTER's root and /fix's under the
      # repository root (FixLoop#mission_root); status names each that exists.
      def dispatch_mission(root, ctx: nil)
        arg = arg_for(ctx)
        return "status mission" unless ["", "status"].include?(arg)

        missions = mission_roots(root).filter_map do |kind, at|
          record = Master::Fix::Mission.current(root: at)
          [kind, record] if record
        end
        return "mission0: none" if missions.empty?

        missions.map { |kind, record| mission_lines(kind, record) }.join("\n\n")
      rescue StandardError => e
        "mission0: #{e.class}: #{e.message}"
      end

      def mission_roots(root)
        fix_root = File.expand_path(root) == Master::ROOT ? Master::REPO_ROOT : root
        [["fold", root], ["fix", fix_root]].uniq { |_, at| File.expand_path(at) }
      end

      def mission_lines(kind, record)
        [
          "mission: #{record["id"]} (#{kind})",
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
