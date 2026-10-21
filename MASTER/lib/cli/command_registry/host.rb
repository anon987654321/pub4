# frozen_string_literal: true

require_relative "../../operator/capability_graph"
require_relative "../../io/exec"
require_relative "../../ground/personal_workspace"
require_relative "../../ground/personal_calendar"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /pair — issue, list, revoke or redeem a pairing code.
      def dispatch_pair(root, ctx: nil)
        arg = arg_for(ctx)
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

      # /owner — local paired owner profile. Values are explicit, bounded and reversible.
      def dispatch_owner(root, ctx: nil)
        return "owner: local-only" if Fiber[:master_visitor] == true

        subject = Master::Device::Agent.owner_subject(root:)
        return "owner: unpaired — use /pair owner [label]" if subject.empty?

        arg = arg_for(ctx)
        case arg
        when "", "status"
          values = Master::Device::OwnerProfile.values(root:, subject:)
          values.empty? ? "owner: no profile fields set" : values.map { |key, value| "#{key}=#{value}" }.join("\n")
        when "intro"
          Master::Device::OwnerProfile.onboarding_prompt(root:, subject:)
        when /\Aforget\s+(\w+)\z/
          Master::Device::OwnerProfile.forget(root:, subject:, key: $1)
          "owner: forgot #{$1}"
        when /\Aset\s+(.+)\z/
          fields = parse_owner_fields($1)
          return "owner: usage /owner set name=... pet_name=... language=... locale=... timezone=... communication_style=... interests=..." if fields.empty?
          Master::Device::OwnerProfile.set(root:, subject:, **fields)
          Master::Device::OwnerProfile.onboarding_prompt(root:, subject:)
        else
          "owner: status | intro | set key=value [...] | forget <key>"
        end
      rescue ArgumentError => e
        "owner0: #{e.message}"
      rescue StandardError => e
        "owner0: unavailable — #{e.class}: #{e.message}"
      end

      def parse_owner_fields(text)
        allowed = Master::Device::OwnerProfile::KEYS
        text.scan(/(#{allowed.join("|")})=(?:"([^"]+)"|'([^']+)'|(\S+))/).each_with_object({}) do |(key, a, b, c), fields|
          fields[key.to_sym] = (a || b || c).to_s.strip
        end
      end

      # /deploy — canonical remote vm23 deployment. Command#review_gate requires
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

      # /device — local Android companion status and ownership boundary.
      def dispatch_device_agent(root, ctx: nil)
        return "device: local-only" if Fiber[:master_visitor] == true

        _word, _rest = subcommand(ctx)
        status = Master::Device::Agent.status(root:)
        paired = status[:paired] ? "paired" : "unpaired"
        owner = status[:owner_label].to_s.empty? ? "" : " owner=#{status[:owner_label]}"
        "device: #{paired}#{owner} id=#{status[:device_id]} last_tick=#{status[:last_tick_at] || "never"}"
      rescue StandardError => e
        "device: unavailable — #{e.class}: #{e.message}"
      end

      # /doctor — bin/doctor's report followed by the security audit.
      # `/doctor device` asks the hardware the host exposes through Termux:API.
      def dispatch_doctor(root, ctx: nil)
        word, rest = subcommand(ctx)
        return dispatch_device(root, ctx: rest) if word == "device"

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
    end
  end
end
