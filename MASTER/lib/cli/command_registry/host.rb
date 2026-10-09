# frozen_string_literal: true

require_relative "../../operator/capability_graph"
require_relative "../../io/exec"

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
