# frozen_string_literal: true

class DomainsController < ActionController::API
  def check
    domain = params.require(:domain).to_s.downcase
    result = Eritel::Registry.current.check(domain)

    render json: result
  rescue ActionController::ParameterMissing
    render json: { error: "domain is required" }, status: :bad_request
  rescue Eritel::RegistryAdapter::UnsupportedOperation => e
    render json: { error: e.message }, status: :service_unavailable
  end
end
