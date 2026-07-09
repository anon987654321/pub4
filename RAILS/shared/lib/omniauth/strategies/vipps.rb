# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Vipps < OmniAuth::Strategies::OAuth2
      option :name, "vipps"
      option :client_options,
             site: "https://api.vipps.no",
             authorize_url: "/access-management-1.0/access/oauth2/auth",
             token_url: "/access-management-1.0/access/oauth2/token"
      option :scope, "openid email name phoneNumber"
      option :provider_ignores_state, true

      uid { raw_info["sub"] || raw_info["userId"] }

      info do
        {
          email: raw_info["email"],
          name: raw_info["name"],
          phone: raw_info["phone_number"] || raw_info["phoneNumber"]
        }
      end

      def raw_info
        @raw_info ||= access_token.get("/vipps-userinfo-api/userinfo").parsed || {}
      rescue StandardError
        @raw_info = {}
      end
    end
  end
end