# frozen_string_literal: true

module Eritel
  class ParticipantAccess
    Result = Data.define(:allowed, :reason)

    def self.check(participant:, mode:)
      return Result.new(true, nil) if mode.to_s == "direct" && participant.nil?

      return Result.new(false, "participant is required") unless participant
      return Result.new(false, "participant is not active") unless participant.active?

      allowed_modes = {
        "registrar" => "registrar",
        "reseller" => "reseller",
        "dns_provider" => "technical",
        "technical_partner" => "technical"
      }

      required_kind = allowed_modes.fetch(mode.to_s) do
        return Result.new(false, "unsupported participant mode")
      end

      actual_kind = allowed_modes.fetch(participant.kind, nil)
      return Result.new(false, "participant role does not permit this mode") unless actual_kind == required_kind

      Result.new(true, nil)
    end
  end
end
