# frozen_string_literal: true

module Master
  module Ground
    # Protocol-level admission for agents that claim to mirror MASTER.
    # This verifies identity and procedure; it does not trust a prompt claim.
    class LawHandshake
      PROTOCOL_VERSION = 1
      Verdict = Data.define(:accepted, :reason, :digest, :protocol_version) do
        def accepted? = accepted == true
      end

      def self.current
        new.verify(
          contract_version: PROTOCOL_VERSION,
          law_digest: Law::Contract.digest,
          protocol: Law::Contract::PROTOCOL
        )
      end

      def verify(contract_version:, law_digest:, protocol:)
        expected = Law::Contract.render
        data = JSON.parse(expected)
        version_ok = Integer(contract_version) == PROTOCOL_VERSION
        digest_ok = law_digest.to_s == data.fetch("law_digest")
        protocol_ok = Array(protocol).map(&:to_s) == data.fetch("protocol")
        reason =
          if !version_ok
            "contract version mismatch"
          elsif !digest_ok
            "law digest mismatch"
          elsif !protocol_ok
            "enforcement protocol mismatch"
          else
            "admitted"
          end
        Verdict.new(
          accepted: version_ok && digest_ok && protocol_ok,
          reason:,
          digest: data.fetch("law_digest"),
          protocol_version: PROTOCOL_VERSION
        )
      rescue StandardError => e
        Verdict.new(accepted: false, reason: "invalid handshake: #{e.message}", digest: Law::Contract.digest,
                    protocol_version: PROTOCOL_VERSION)
      end

      def export
        JSON.parse(Law::Contract.render).merge(
          "handshake" => {
            "required" => true,
            "admission" => "present this contract_version, law_digest and protocol verbatim"
          }
        )
      end
    end
  end
end
