# frozen_string_literal: true

module Api
  module V1
    # JSON, authenticated by an API key in Authorization: Bearer mk_live_… .
    # Not ApplicationController: the API needs no container, locale or face.
    class BaseController < ActionController::API
      before_action :authenticate_key!

      private

      def authenticate_key!
        token = request.authorization.to_s.delete_prefix("Bearer ").strip
        @api_key = ApiKey.authenticate(token)
        refuse(:unauthorized, "invalid_key") unless @api_key
      end

      def refuse(status, error, **details) = render(json: { error:, **details }, status:)
    end
  end
end
