# frozen_string_literal: true

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
          { pairing: status, device: device }.inspect
        when /\Aowner(?:\s+(.*))?\z/
          return "pair: local owner pairing requires Android/Termux" unless Master::Device.android? && Fiber[:master_visitor] != true

          label = $1.to_s.strip
          result = Master::Device::Agent.claim_owner!(root:, label:)
          [Master::Ground::Pairing.redeem_notice(result), result[:onboarding]].compact.join("\n")
        when /\Aissue(?:\s+(.*))?\z/
          issued = Master::Ground::Pairing.issue(root:, label: $1.to_s.strip)
          "pair code #{issued[:code]} expires in #{issued[:expires_in]}s — redeem via /pair #{issued[:code]} or the face field"
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
        [body, audit].reject { |part| part.to_s.strip.empty? }.join("\n")
      end
    end
  end
end
