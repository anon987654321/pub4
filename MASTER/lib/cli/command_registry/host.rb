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
          label = $1.to_s.strip
          result = Master::Device::Agent.claim_owner!(root:, label:)
          Master::Ground::Pairing.redeem_notice(result)
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

      # /device — local Android companion status and ownership boundary.
      def dispatch_device(root, ctx: nil)
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
