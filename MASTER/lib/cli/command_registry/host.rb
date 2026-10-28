# frozen_string_literal: true

require "shellwords"
require_relative "../skills"
require_relative "../../operator/capability_graph"
require_relative "../../io/exec"
require_relative "../../ground/personal_workspace"
require_relative "../../device/owner_preferences"
require_relative "../../ground/personal_calendar"
require_relative "../../ground/assistant_tasks"
require_relative "../../ground/capability_catalog"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /pair — issue, list, revoke or redeem a pairing code.
      def dispatch_pair(root, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        if Fiber[:master_visitor] == true
          alphabet = Master::Ground::Pairing::ALPHABET
          code_attempt = arg.length == Master::Ground::Pairing::CODE_BYTES &&
                         arg.upcase.each_char.all? { |character| alphabet.include?(character) }
          return "pair: local-only; visitors may only redeem a pairing code" unless code_attempt
        end

        case arg
        when "", "status"
          status = Master::Ground::Pairing.status
          device = Master::Device::Agent.status(root:)
          { pairing: status, device: }.inspect
        when /\Aowner(?:\s+(.*))?\z/
          return "pair: local owner pairing requires Android/Termux" unless Master::Device.android? && Fiber[:master_visitor] != true

          label = $1.to_s.strip
          result = Master::Device::Agent.claim_owner!(root:, label:)
          [Master::Ground::Pairing.redeem_notice(result), result[:onboarding]].compact.join("\n")
        when /\Aissue(?:\s+(.*))?\z/
          issued = Master::Ground::Pairing.issue(root:, label: $1.to_s.strip)
          "pair code #{issued[:code]} expires in #{issued[:expires_in]}s — redeem via /pair #{issued[:code]} or the face field"
        when "release"
          return "pair: local-only" unless Fiber[:master_visitor] != true
          subject = Master::Device::Agent.release_owner!(root:)
          "pair: released #{subject}"
        when "list"
          rows = Master::Ground::Pairing.list(root:)
          return "pair: no allowlist entries" if rows.empty?

          rows.map { |row| "#{row[:subject]} #{row[:label]}".strip }.join("\n")
        when /\Arevoke\s+(\S+)\z/
          Master::Ground::Pairing.revoke($1, root:) ? "pair: revoked" : "pair: not found"
        else
          result = Master::Ground::Pairing.redeem(arg.split.first, root:)
          return "pair: invalid or expired code" unless result

          Fiber[:master_paired] = true
          Fiber[:master_pair_subject] = result[:subject]
          Master::Ground::Pairing.redeem_notice(result)
        end
      end

      # /privacy is local-only. Personal memory and the explicitly imported,
      # read-only calendar use subject-bound grants; device, external messaging and
      # financial capabilities remain unavailable until their adapters enforce policy.
      def dispatch_privacy(root, ctx: nil)
        return "privacy: local-only; visitors cannot grant personal capabilities" if Fiber[:master_visitor] == true

        subject = Fiber[:master_pair_subject].to_s.strip
        if subject.empty? && defined?(Master::Device::Agent) && Master::Device.respond_to?(:android?) &&
            Master::Device.android? && Master::Device::Agent.paired?(root:)
          subject = Master::Device::Agent.owner_subject(root:).to_s
        end
        return "privacy: no paired subject; pair the local owner before enabling personal memory" if subject.empty?

        permissions = Master::Ground::PersonalPermissions.new(root:)
        arg = arg_for(ctx).to_s.strip.downcase
        case arg
        when "", "status"
          active = permissions.allowed?(
            scope: "personal_memory", subject:, purpose: Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE,
          )
          calendar = permissions.allowed?(
            scope: "calendar_read", subject:, purpose: Master::Ground::PersonalCalendar::READ_PERMISSION_PURPOSE,
          )
          "privacy: personal profile and memory #{active ? "enabled" : "disabled"}; local calendar #{calendar ? "enabled" : "disabled"}; consent is bound to this paired subject"
        when "grant personal_memory"
          permissions.grant(
            scope: "personal_memory", subject:, confirmed_by: "local operator",
            purpose: Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE,
          )
          "privacy: personal profile and memory enabled for this paired subject"
        when "grant calendar_read"
          permissions.grant(
            scope: "calendar_read", subject:, confirmed_by: "local operator",
            purpose: Master::Ground::PersonalCalendar::READ_PERMISSION_PURPOSE,
          )
          "privacy: local calendar reading enabled for this paired subject"
        when /\Arevoke calendar_read(?:\s+(.+))?\z/
          reason = Regexp.last_match(1).to_s.strip
          revoked = permissions.revoke(
            scope: "calendar_read", subject:, confirmed_by: "local operator",
            reason: reason.empty? ? "calendar reading revoked by owner" : reason,
          )
          revoked ? "privacy: local calendar reading disabled immediately" : "privacy: no active calendar-reading grant"
        when "memory show", "memory export"
          data = Master::Ground::PersonalWorkspace.snapshot(root:, subject:)
          data.map { |name, body| "#{name}\n#{body}" }.join("\n\n")
        when "memory forget --confirm"
          Master::Ground::PersonalWorkspace.forget_memory!(root:, subject:)
          "privacy0 at master0: durable memory cleared; USER.md profile retained"
        when /\Amemory forget(?:\s.*)?\z/
          "privacy: erasing durable memory requires the exact command /privacy memory forget --confirm; the USER.md profile is retained"
        when /\Arevoke personal_memory(?:\s+(.+))?\z/
          reason = Regexp.last_match(1).to_s.strip
          revoked = permissions.revoke(
            scope: "personal_memory", subject:, confirmed_by: "local operator",
            reason: reason.empty? ? "personal memory revoked by owner" : reason,
          )
          revoked ? "privacy: personal profile and memory disabled immediately" : "privacy: no active personal-memory grant"
        else
          "privacy: status | grant personal_memory | revoke personal_memory"
        end
      rescue StandardError => e
        "privacy0: unavailable — #{e.class}: #{e.message}"
      end

      # /preferences — consented, subject-scoped interaction preferences.
      def dispatch_preferences(root, ctx: nil)
        return "preferences: local-only; visitors cannot access personal preferences" if Fiber[:master_visitor] == true

        subject = Fiber[:master_pair_subject].to_s.strip
        if subject.empty? && defined?(Master::Device::Agent) && Master::Device.respond_to?(:android?) &&
            Master::Device.android? && Master::Device::Agent.paired?(root:)
          subject = Master::Device::Agent.owner_subject(root:).to_s.strip
        end
        return "preferences: no paired subject; pair the local owner first" if subject.empty?
        unless Master::Device::OwnerPreferences.permission_granted?(root:, subject:)
          return "preferences: disabled; explicitly enable with /privacy grant personal_memory in the local paired session"
        end

        args = Shellwords.split(arg_for(ctx).to_s)
        action = args.shift.to_s.downcase
        preferences = Master::Device::OwnerPreferences
        case action
        when "", "show", "status"
          requested_scope = args.first
          return "preferences: usage /preferences show [#{preferences::SCOPES.join("|")}]" if args.size > 1
          state = preferences.status(root:, subject:)
          scope = requested_scope ? preferences.normalize_scope(requested_scope) : "all"
          scopes = if requested_scope.nil? || scope == "all"
                     preferences::SCOPES
                   else
                     %w[all].concat([scope])
                   end
          lines = ["preferences: learning=#{state.fetch("learning_enabled") ? "on" : "off"}"]
          scopes.each do |name|
            state.fetch("preferences").fetch(name, {}).each do |key, entry|
              reason = entry["reason"] ? ", reason=#{entry.fetch("reason")}" : ""
              lines << "#{name} #{key}=#{entry.fetch("value")} (source=#{entry.fetch("source")}, confidence=#{entry.fetch("confidence")}#{reason})"
            end
          end
          if state.fetch("suggestions").empty?
            lines << "preferences: no pending suggestions"
          else
            state.fetch("suggestions").each do |entry|
              lines << "suggestion #{entry.fetch("id")} #{entry.fetch("scope")} #{entry.fetch("key")}=#{entry.fetch("value")} (origin=#{entry.fetch("origin", "owner")}, evidence=#{entry.fetch("evidence_count", 0)}, confidence=#{entry.fetch("confidence")}): #{entry.fetch("reason")}"
            end
          end
          lines.join("\n")
        when "set"
          key_value = args.shift.to_s
          key, value = key_value.split("=", 2)
          options = parse_preference_options(args, %w[scope])
          return "preferences: usage /preferences set KEY=VALUE [scope=SCOPE]" unless key && value && options
          result = preferences.set(root:, subject:, key:, value:, scope: options.fetch("scope", "all"))
          "preferences: set #{result.fetch("scope")} #{result.fetch("key")}=#{result.fetch("value")}"
        when "suggest"
          key_value = args.shift.to_s
          key, value = key_value.split("=", 2)
          options = parse_preference_options(args, %w[scope reason confidence])
          return "preferences: usage /preferences suggest KEY=VALUE [scope=SCOPE] [reason=\"...\"] [confidence=0.7]" unless key && value && options
          confidence = options.key?("confidence") ? Float(options.fetch("confidence")) : 0.7
          candidate = preferences.suggest(
            root:, subject:, key:, value:, scope: options.fetch("scope", "all"),
            reason: options.fetch("reason", "Preference candidate"),
            confidence:,
          )
          "preferences: suggestion #{candidate.fetch("id")} staged but inactive; inspect with /preferences show and use /preferences accept #{candidate.fetch("id")} to activate"
        when "accept"
          return "preferences: usage /preferences accept <suggestion-id>" unless args.size == 1
          candidate = preferences.accept(root:, subject:, id: args.first)
          "preferences: accepted #{candidate.fetch("id")} — #{candidate.fetch("scope")} #{candidate.fetch("key")}=#{candidate.fetch("value")}"
        when "reject"
          return "preferences: usage /preferences reject <suggestion-id>" unless args.size == 1
          preferences.reject(root:, subject:, id: args.first) ? "preferences: suggestion rejected" : "preferences: suggestion not found"
        when "forget"
          key = args.shift.to_s
          options = parse_preference_options(args, %w[scope])
          return "preferences: usage /preferences forget KEY [scope=SCOPE]" if key.empty? || !options
          preferences.forget(root:, subject:, key:, scope: options.fetch("scope", "all")) ?
            "preferences: forgot #{options.fetch("scope", "all")} #{key}" : "preferences: no such preference"
        when "learn"
          return "preferences: usage /preferences learn on|off" unless args.size == 1 && %w[on off].include?(args.first.downcase)
          enabled = args.first.downcase == "on"
          preferences.set_learning(root:, subject:, enabled:)
          "preferences: learning #{enabled ? "enabled" : "disabled"}; repeated low-risk correction signals can stage inactive suggestions; owner acceptance is still required"
        when "reset"
          return "preferences: reset requires the exact command /preferences reset --confirm" unless args == ["--confirm"]
          preferences.reset(root:, subject:)
          "preferences: reset to defaults; learning is off"
        when "export"
          return "preferences: usage /preferences export" unless args.empty?
          preferences.export(root:, subject:)
        else
          "preferences: show [scope] | set KEY=VALUE [scope=SCOPE] | suggest KEY=VALUE [scope=SCOPE] [reason=\"...\"] | accept ID | reject ID | forget KEY [scope=SCOPE] | learn on|off | reset --confirm | export"
        end
      rescue ArgumentError => e
        "preferences0: #{e.message}"
      rescue StandardError => e
        "preferences0: unavailable — #{e.class}: #{e.message}"
      end

      def parse_preference_options(tokens, allowed)
        pairs = tokens.map do |token|
          key, value = token.split("=", 2)
          return nil unless value && allowed.include?(key)
          [key, value]
        end
        return nil unless pairs.map(&:first).uniq.size == pairs.size

        pairs.to_h
      end

      # /agenda reads an owner-imported local iCalendar export; it never mutates
      # the provider calendar or reaches a remote service.
      def dispatch_agenda(root, ctx: nil)
        return "agenda: local-only; visitors cannot access a personal calendar" if Fiber[:master_visitor] == true

        subject = Fiber[:master_pair_subject].to_s.strip
        if subject.empty? && defined?(Master::Device::Agent) && Master::Device.respond_to?(:android?) &&
            Master::Device.android? && Master::Device::Agent.paired?(root:)
          subject = Master::Device::Agent.owner_subject(root:).to_s
        end
        return "agenda: pair this local session before accessing a personal calendar" if subject.empty?

        calendar = Master::Ground::PersonalCalendar.new(root:)
        arg = arg_for(ctx).to_s.strip
        case arg
        when "", "today", "status"
          if arg == "status"
            state = calendar.status(subject:)
            return state[:imported] ?
              "agenda: local calendar imported; #{state[:event_count]} events, #{state[:recurring_series]} recurring series not expanded" :
              "agenda: no local calendar imported; use /agenda import /path/to/calendar.ics"
          end
          render_agenda(calendar.events_for(subject:, date: Date.today))
        when /\Aimport\s+(.+)\z/m
          source_args = Shellwords.split(Regexp.last_match(1))
          return "agenda: usage is /agenda import /path/to/calendar.ics" unless source_args.size == 1

          imported = calendar.import!(subject:, source: source_args.first)
          "agenda: imported #{imported[:event_count]} events from #{imported[:filename]}; #{imported[:recurring_series]} recurring series will be reported but are not expanded"
        when /\A\d{4}-\d{2}-\d{2}\z/
          render_agenda(calendar.events_for(subject:, date: Date.iso8601(arg)))
        else
          "agenda: status | import /path/to/calendar.ics | today | YYYY-MM-DD"
        end
      rescue StandardError => e
        "agenda0: unavailable — #{e.class}: #{e.message}"
      end

      def render_agenda(result)
        events = result.fetch(:events)
        date = result.fetch(:date).iso8601
        lines = events.map do |event|
          when_text = event.all_day ? "all day" : [event.clock, event.timezone].compact.reject(&:empty?).join(" ")
          location = event.location.empty? ? "" : " — #{event.location}"
          series = event.recurring ? " (recurring series; DTSTART only)" : ""
          "#{when_text} #{event.summary}#{location}#{series}".strip
        end
        lines = ["agenda: no events for #{date} (#{result.fetch(:total_events)} imported)"] if lines.empty?
        lines << "agenda: note: #{result.fetch(:recurring_series)} recurring series are not expanded; verify their occurrences in the source calendar" if result.fetch(:recurring_series).positive?
        lines.join("\n")
      end

      # /skill reviews declared capability contracts and allows an explicit
      # local operator to approve or revoke one exact content revision.
      def dispatch_skill(root, ctx: nil, approval_path: File.join(Dir.home, ".master", "skill_approvals.yml"))
        return "skill: local operator only; visitors cannot approve executable skill revisions" if Fiber[:master_visitor] == true

        args = Shellwords.split(arg_for(ctx).to_s)
        action = args.shift.to_s.downcase
        skills = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!)

        case action
        when "", "list", "review"
          rows = skills.contract_inventory.select { |row| row[:declared] }
          return "skill0 at master0: no declared skill contracts; legacy skills remain unreviewed and compatible" if rows.empty?

          rows.map do |row|
            errors = row[:errors].empty? ? "" : " errors=#{row[:errors].join(",")}"
            "#{row[:name]} revision=#{row[:revision]} status=#{row[:status]} risk=#{row[:risk]} " \
              "promotable=#{row[:promotable] ? "yes" : "no"} approved=#{row[:operator_approved] ? "yes" : "no"} " \
              "active=#{row[:active_for_trigger] ? "yes" : "no"}#{errors}"
          end.join("\n")
        when "inspect"
          return "skill: usage /skill inspect <name>" unless args.length == 1

          row = skills.contract_for(args.first)
          return "skill: not found or has no contract" unless row

          [
            "name=#{row[:name]}",
            "revision=#{row[:revision]}",
            "status=#{row[:status]} risk=#{row[:risk]}",
            "declared=#{row[:declared]} promotable=#{row[:status] == :candidate && row[:errors].empty?}",
            "operator_approved=#{row[:operator_approved]} active=#{row[:active_for_trigger]}",
            "capabilities=#{Array(row[:required_capabilities]).join(",")}",
            "laws=#{Array(row[:law_ids]).join(",")}",
            "fixtures=#{Array(row[:fixture_refs]).join(",")}",
            "errors=#{Array(row[:errors]).join(",")}"
          ].join("\n")
        when "approve"
          unless args.length == 3 && args[2] == "--confirm"
            return "skill: approval requires the exact command /skill approve <name> <full SHA-256 revision> --confirm"
          end

          approved_by = ENV["USER"].to_s.strip
          approved_by = "local-operator" if approved_by.empty?
          row = skills.approve_revision!(name: args[0], revision: args[1], approved_by:)
          "skill0 at master0: approved #{args[0]} revision=#{args[1]} by=#{approved_by}; activation is limited to this exact revision"
        when "revoke"
          unless args.length == 3 && args[2] == "--confirm"
            return "skill: revocation requires the exact command /skill revoke <name> <full SHA-256 revision> --confirm"
          end

          removed = skills.revoke_revision!(name: args[0], revision: args[1])
          removed ? "skill0 at master0: revoked #{args[0]} revision=#{args[1]}" :
            "skill0 at master0: no matching approval for #{args[0]} revision=#{args[1]}"
        else
          "skill: list | inspect <name> | approve <name> <full SHA-256 revision> --confirm | revoke <name> <full SHA-256 revision> --confirm"
        end
      rescue ArgumentError => e
        "skill0: #{e.message}"
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.skill", event_bus: nil)
        "skill0: unavailable — #{e.class}: #{e.message}"
      end

      # /task is a local, durable personal task board. It records supplied
      # verification evidence but never executes actions; a due task rings only in an open session.
      def dispatch_task(root, ctx: nil)
        return "task: local-owner only; visitor sessions cannot access personal tasks" if Fiber[:master_visitor] == true

        args = Shellwords.split(arg_for(ctx).to_s)
        action = args.shift.to_s.downcase
        tasks = Master::Ground::AssistantTasks.new(root:)
        case action
        when "", "list"
          render_task_list(tasks.call(action: "list"))
        when "search"
          query = args.join(" ")
          return "task: usage /task search <words>" if query.empty?
          render_task_list(tasks.call(action: "list", query:))
        when "create"
          title = args.join(" ")
          return "task: usage /task create <title>" if title.empty?
          task = tasks.call(action: "create", title:)
          "task: created #{task["id"]} [#{task["state"]}] #{task["title"]}"
        when "show"
          return "task: usage /task show <id>" unless args.size == 1
          render_task(tasks.call(action: "show", id: args.first))
        when "step", "add-step"
          id = args.shift.to_s
          title = args.join(" ")
          return "task: usage /task step <id> <step title>" if id.empty? || title.empty?
          step = tasks.call(action: "add_step", id:, step_title: title).fetch("step")
          "task: step #{step["id"]} added to #{id} — #{step["title"]}"
        when "start-step", "block-step", "verify-step"
          id = args.shift.to_s
          step_id = args.shift.to_s
          detail = args.join(" ")
          return "task: usage /task #{action} <id> <step-id> <note or evidence>" if [id, step_id, detail].any?(&:empty?)
          verb = { "start-step" => "start_step", "block-step" => "block_step", "verify-step" => "verify_step" }.fetch(action)
          payload = verb == "verify_step" ? { evidence: detail } : { note: detail }
          result = tasks.call(action: verb, id:, step_id:, **payload)
          "task: #{action} #{result.fetch("step")["state"]} — #{result.fetch("step")["title"]}#{verb == "verify_step" ? " (evidence recorded; not independently authenticated)" : ""}"
        when "block", "resume", "complete"
          id = args.shift.to_s
          detail = args.join(" ")
          return "task: usage /task #{action} <id> <reason or evidence>" if id.empty? || detail.empty?
          payload = action == "complete" ? { evidence: detail } : { note: detail }
          result = tasks.call(action:, id:, **payload)
          "task: #{result["id"]} [#{result["state"]}] #{result["title"]}#{action == "complete" ? " (completion recorded against supplied evidence)" : ""}"
        when "update"
          id = args.shift.to_s
          field = args.shift.to_s
          value = args.join(" ")
          return "task: usage /task update <id> title|description|priority|due_at <value>" if id.empty? || value.empty?
          return "task: update field must be title, description, priority or due_at" unless %w[title description priority due_at].include?(field)
          task = tasks.call(action: "update", id:, **{ field.to_sym => value })
          "task: updated #{task["id"]} — #{task["title"]}"
        else
          "task: list | search <words> | create <title> | show <id> | step <id> <title> | start-step <id> <step-id> <note> | verify-step <id> <step-id> <evidence> | block-step <id> <step-id> <reason> | block <id> <reason> | resume <id> <note> | complete <id> <evidence> | update <id> <field> <value>"
        end
      rescue ArgumentError, Master::Ground::AssistantTasks::Error => e
        "task0: #{e.message}"
      rescue StandardError => e
        "task0: unavailable — #{e.class}: #{e.message}"
      end

      def render_task_list(result)
        rows = result.fetch("tasks")
        lines = rows.map do |task|
          verified = Array(task["steps"]).count { |step| step["state"] == "verified" }
          due = task["due_at"].to_s.empty? ? "" : " due=#{task["due_at"]}"
          overdue = task["overdue"] ? " overdue" : ""
          "#{task["id"]} [#{task["state"]}] #{task["title"]}#{due}#{overdue} steps=#{verified}/#{Array(task["steps"]).size}"
        end
        lines = ["task: no tasks yet; create one with /task create <title>"] if lines.empty?
        lines << "task: showing #{rows.size} of #{result["count"]}" if result["truncated"]
        lines << "task: due dates are local metadata; no background notifications are sent"
        lines.join("\n")
      end

      def render_task(task)
        lines = ["#{task["id"]} [#{task["state"]}] #{task["title"]}",
                 "priority=#{task["priority"]} due=#{task["due_at"] || "none"}"]
        lines << task["description"] unless task["description"].to_s.empty?
        Array(task["steps"]).each do |step|
          lines << "  #{step["id"]} [#{step["state"]}] #{step["title"]}"
          lines << "    evidence: #{step["evidence"]}" unless step["evidence"].to_s.empty?
          lines << "    note: #{step["note"]}" unless step["note"].to_s.empty?
        end
        lines << "verification: #{task["verification_note"]}" unless task["verification_note"].to_s.empty?
        lines.join("\n")
      end

      # Show the universal inventory without running tools or loading provider code.
      def dispatch_capabilities(root, ctx: nil)
        return "capabilities: local operator only; visitor inventory is restricted" if Fiber[:master_visitor] == true

        args = Shellwords.split(arg_for(ctx).to_s)
        action = args.shift.to_s.downcase
        action = "list" if action.empty?
        case action
        when "list"
          result = Master::Ground::CapabilityCatalog.call(action: "list", root:)
          lines = ["capabilities: profile=#{result["profile"]}"]
          result.fetch("core_tools").each do |tool|
            profile = tool["allowed_by_current_profile"] ? "profile" : "withheld"
            tier = tool["elevated_required"] ? "elevated" : "standard"
            enabled = tool["boot_enabled"] ? "enabled" : "disabled"
            lines << "tool #{tool["name"]} [#{profile}, #{tier}, #{enabled}] — #{tool["description"]}"
          end
          result.fetch("plugins").each do |plugin|
            actions = plugin.fetch("observation_actions").map { |row| row["name"] }.join(",")
            lines << "plugin #{plugin["id"]} [#{plugin["status"]}; observations=#{actions.empty? ? "none" : actions}] — #{plugin["description"]}"
          end
          lines << "capabilities: metadata only; registration does not prove runtime availability"
          lines.join("\n")
        when "search"
          query = args.join(" ")
          return "capabilities: usage /capabilities search <words>" if query.empty?
          result = Master::Ground::CapabilityCatalog.call(action: "search", query:, root:)
          result.fetch("results").map { |row| "#{row["kind"]} #{row["name"] || row["id"]} — #{row["description"]}" }.join("\n").then { |body| body.empty? ? "capabilities: no matches" : body }
        when "describe"
          name = args.join(" ")
          return "capabilities: usage /capabilities describe <tool|plugin|plugin:id:action>" if name.empty?
          JSON.pretty_generate(Master::Ground::CapabilityCatalog.call(action: "describe", name:, root:))
        else
          "capabilities: list | search <words> | describe <tool|plugin|plugin:id:action>"
        end
      rescue ArgumentError => e
        "capabilities0: #{e.message}"
      rescue StandardError => e
        "capabilities0: unavailable — #{e.class}: #{e.message}"
      end

      SCREEN_NAME = /\A[\w.-]{1,40}\z/

      # /screen — keep MASTER running in a GNU screen session you can leave and come back to.
      # It starts bin/master detached and names the command that reattaches; it never
      # attaches itself, because this terminal is already inside a session.
      def dispatch_screen(root, ctx: nil)
        word = arg_for(ctx).split(/\s+/).first.to_s
        return "screen: not installed" unless screen_path
        return screen_list if word == "list"

        name = word.empty? ? "master" : word
        return "screen: names are letters, digits, dot, dash and underscore" unless name.match?(SCREEN_NAME)
        return "screen: #{name} is running; reattach with: screen -r #{name}" if screen_running?(name)

        _out, status = Master::Io::Exec.capture2e(screen_path, "-dmS", name, File.join(root, "bin", "master"), chdir: root, timeout: 15)
        status.success? ? "screen: started #{name}; attach with: screen -r #{name}" : "screen: could not start #{name}"
      end

      def screen_path = Master::Io::Exec.which("screen")

      def screen_list
        out, = Master::Io::Exec.capture2e(screen_path, "-ls", timeout: 10)
        out.to_s.strip
      end

      def screen_running?(name) = screen_list.match?(/\d+\.#{Regexp.escape(name)}\s/)

      # /deploy — canonical remote vm23 deployment. Command#review_check requires
      # --confirm before this handler can mutate production.
      def dispatch_deploy(_root, ctx: nil)
        target = arg_for(ctx).split(/\s+/).reject { |token| token.start_with?("--") }.first.to_s.downcase
        target = "all" if target.empty?
        allowed = %w[all master brgen amber bsdports]
        return "deploy: usage /deploy all|master|brgen|amber|bsdports --confirm" unless allowed.include?(target)

        operator = File.join(MasterPaths.repo, "MASTER", "bin", "operator")
        output, status = Master::Io::Exec.capture2e(
          RbConfig.ruby, operator, "vps", "deploy", target, "--remote",
          chdir: MasterPaths.repo
        )
        summary = deploy_summary(output, status)
        return Result.ok(summary) if status.success?

        Result.err("deploy: #{summary}", category: :infrastructure)
      end

      def deploy_summary(output, status)
        lines = output.to_s.lines.map(&:strip).reject(&:empty?)
        success_line = lines.reverse.find { |line| line.match?(/\bvps-deploy:\s+.+\b(?:ok|complete|ready)\b/i) }
        return "remote: #{success_line}" if status.success? && success_line

        decisive = lines.reverse.find { |line| line.match?(/\b(?:fatal|failed|refused|error|aborted|conflict|not ready|did not|could not)\b/i) }
        detail = decisive || lines.last || "no remote output"
        detail = lines.last(2).join(" | ") if decisive && lines.last != decisive && lines.last.length < 90
        detail = detail[0, 150]
        status.success? ? "remote: #{detail}" : "remote exit #{status.exitstatus || "signal"}: #{detail}"
      end

      # /android and /ios are the public mobile onboarding entrypoints. The
      # platform selects the starting lane; capability ownership stays below
      # the command surface.
      def dispatch_android(root, ctx: nil)
        dispatch_mobile_onboarding(:android, root, ctx:)
      end

      def dispatch_ios(root, ctx: nil)
        dispatch_mobile_onboarding(:ios, root, ctx:)
      end

      def dispatch_mobile_onboarding(platform, root, ctx: nil)
        label = arg_for(ctx)
        Master::Device::Onboarding.new(
          android: platform == :android,
          root:,
        ).mobile_start!(platform:, label:)
      rescue ArgumentError => e
        "#{platform}0: #{e.message}"
      rescue StandardError => e
        "#{platform}0: unavailable — #{e.class}: #{e.message}"
      end

      # /wake — explicit microphone wake-word consent and status.
      def dispatch_wake(root, ctx: nil)
        return "wake: local-only" if Fiber[:master_visitor] == true
        return "wake: Android/Termux only" unless Master::Device.android? && Master::Device.termux?

        wake = Master::Device::WakeWord.new(root:)
        word, rest = subcommand(ctx)
        case word
        when "", "status"
          "wake: #{wake.enabled? ? "on" : "off"} phrases=#{wake.phrases.join(", ")}"
        when "on", "enable"
          pet = Master::Device::Agent.owner_subject(root:)
          phrases = ["hey master"]
          unless pet.empty?
            profile = Master::Device::OwnerProfile.values(root:, subject: pet)
            name = profile["pet_name"].to_s.strip
            phrases << "hey #{name.downcase}" unless name.empty?
          end
          wake.enable!(phrases:)
          "wake: on — #{wake.phrases.join(", ")}"
        when "off", "disable"
          wake.disable!
          "wake: off"
        else
          "wake: status | on | off"
        end
      rescue StandardError => e
        "wake0: unavailable — #{e.class}: #{e.message}"
      end

      # /doctor — bin/doctor's report followed by the security audit.
      # `/doctor device` asks the hardware the host exposes through Termux:API.
      def dispatch_doctor(root, ctx: nil)
        word, rest = subcommand(ctx)
        return dispatch_device(root, ctx: rest) if word == "device"
        return dispatch_tools(root, ctx: rest) if word == "tools"

        script = File.join(root, "bin", "doctor")
        body = if File.file?(script)
                 out, err, status = Master::Io::Exec.capture3(Gem.ruby, script, chdir: root)
                 text = [out, err].map(&:strip).reject(&:empty?).join("\n")
                 status.success? ? text : "#{text}\ndoctor: exit #{status.exitstatus}"
               else
                 "doctor: missing #{script}"
               end
        audit = Master::Ground::SecurityAudit.report(root:)
        capabilities = ::Operator::CapabilityGraph.new(root:).render(model: ENV["MASTER_MODEL"])
        [body, audit, capabilities].reject { |part| part.to_s.strip.empty? }.join("\n")
      end

      # /doctor tools lists the tool calls whose outcome nobody knows: each one
      # blocks a repeat with the same arguments. `/doctor tools reconcile <id>
      # <outcome> <evidence>` records what the operator verified and lifts it.
      def dispatch_tools(root, ctx: nil)
        bus = Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root:),
                                          evidence_log: Master::Trace::Log::Evidence.new(root:))
        observer = Master::Trace::ToolObserver.new(bus:)
        verb, id, outcome, evidence = arg_for(ctx).split
        if verb == "reconcile"
          held = observer.reconcile_invocation!(invocation_id: id, outcome:, evidence_ref: evidence)
          return "tools0: #{held.tool} #{held.invocation_id} reconciled #{outcome}"
        end

        held = observer.unresolved
        return "tools0: no unresolved tool outcome" if held.empty?

        outcomes = Master::Trace::ToolObserver::RECONCILIATIONS.join("|")
        (held.map { |identity| "tools0: #{identity.invocation_id} #{identity.tool} #{identity.tier} unresolved" } <<
          "reconcile with /doctor tools reconcile <id> <#{outcomes}> <evidence_ref>").join("\n")
      rescue ArgumentError => e
        "tools0: #{e.message}"
      end
    end
  end
end
