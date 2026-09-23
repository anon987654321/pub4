# frozen_string_literal: true

require "json"

module Master
  module Ground
    # Protocol-level admission for agents that claim to mirror MASTER.
    # This verifies identity and procedure; it does not trust a prompt claim.
    class LawHandshake
      PROTOCOL_VERSION = 1
      Verdict = Data.define(:accepted, :reason, :digest, :protocol_version) do
        def accepted? = accepted == true
      end

      # law/law.rb proves ~118 rule fixtures at load, so it is required lazily
      # by whoever first needs Law::Contract rather than eagerly at boot — the
      # same idiom lib/ground/rules.rb and every other Law caller in this tree
      # already follows.
      def self.ensure_law!
        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
      end

      module Admission
        module_function
        def enable!
          LawHandshake.ensure_law!
          @digest = Law::Contract.digest
          @enabled = true
          @digest
        end
        def disable!
          @enabled = false
          @digest = nil
        end
        def enabled? = @enabled == true
        def admitted? = enabled? && @digest == Law::Contract.digest
        def require!
          return true unless enabled?
          return true if admitted?
          raise SecurityError, "constitutional admission expired — executable law digest changed"
        end
        def digest = @digest
      end

      def self.current
        ensure_law!
        new.verify(
          contract_version: PROTOCOL_VERSION,
          law_digest: Law::Contract.digest,
          protocol: Law::Contract::PROTOCOL
        )
      end

      def verify(contract_version:, law_digest:, protocol:)
        self.class.ensure_law!
        data = JSON.parse(Law::Contract.render)
        version_ok = Integer(contract_version) == PROTOCOL_VERSION
        digest_ok = law_digest.to_s == data.fetch("law_digest")
        protocol_ok = Array(protocol).map(&:to_s) == data.fetch("protocol")
        Verdict.new(
          accepted: version_ok && digest_ok && protocol_ok,
          reason: handshake_reason(version_ok, digest_ok, protocol_ok),
          digest: data.fetch("law_digest"),
          protocol_version: PROTOCOL_VERSION
        )
      rescue StandardError => e
        Verdict.new(accepted: false, reason: "invalid handshake: #{e.message}", digest: Law::Contract.digest,
                    protocol_version: PROTOCOL_VERSION)
      end

      def handshake_reason(version_ok, digest_ok, protocol_ok)
        return "contract version mismatch" unless version_ok
        return "law digest mismatch" unless digest_ok
        return "enforcement protocol mismatch" unless protocol_ok

        "admitted"
      end

      def export
        self.class.ensure_law!
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
