# frozen_string_literal: true

class DomainsController < ActionController::API
  def check
    domain = params.require(:domain).to_s
    policy = Eritel::DomainPolicy.check(domain)

    return render json: policy_payload(policy), status: :unprocessable_entity unless policy.allowed

    result = Eritel::Registry.current.check(policy.name)
    render json: result.merge(policy: "accepted")
  rescue ActionController::ParameterMissing
    render json: { error: "domain is required" }, status: :bad_request
  rescue Eritel::RegistryAdapter::UnsupportedOperation => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def policy_payload(result)
    {
      domain: result.name,
      available: false,
      policy: "rejected",
      reason: result.reason
    }
  end
end
