# frozen_string_literal: true

module Shared
  # Shared-secret gate for loopback/internal service callers (MASTER bridges).
  module InternalTokenAuth
    extend ActiveSupport::Concern

    included do
      allow_unauthenticated_access if respond_to?(:allow_unauthenticated_access)
      before_action :authenticate_internal_caller
      skip_before_action :verify_authenticity_token, raise: false
    end

    private

    def authenticate_internal_caller
      expected = ENV["MASTER_INTERNAL_TOKEN"].to_s
      given = request.headers["X-Internal-Token"].to_s
      given = request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "").strip if given.empty?
      return head :unauthorized if expected.empty? || given.empty?
      head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, given)
    end
  end
end
