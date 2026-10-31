# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/lint {"files": [{"path": "app/models/user.rb", "source": "…"}]}
    # One file is one check against the key's monthly quota, counted before the
    # scan so a request that does not fit costs nothing.
    class LintController < BaseController
      rate_limit to: 60, within: 1.minute, by: -> { @api_key.id },
                 with: -> { refuse(:too_many_requests, "rate_limited") }

      def create
        inputs = LawCheck.inputs(params[:files])
        return refuse(:payment_required, "subscription_inactive") unless @api_key.entitling?

        usage = @api_key.charge!(inputs.size)
        return refuse(:too_many_requests, "quota_exhausted", usage: @api_key.usage.to_h) unless usage

        render json: { findings: LawCheck.call(inputs), usage: usage.to_h }
      rescue LawCheck::Invalid => e
        refuse(:unprocessable_entity, "invalid_request", detail: e.message)
      end
    end
  end
end
