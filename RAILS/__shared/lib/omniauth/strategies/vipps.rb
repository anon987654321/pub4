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
# No provider_ignores_state. It was set true here, which turns off OmniAuth's
# CSRF check on the callback: without it an attacker can complete the round
# trip with their own authorization code and bind the victim's session to an
# account the attacker controls. Vipps is a standards-compliant OIDC provider
# and echoes `state`, so there was nothing to work around; the line arrived
# in an automated polish pass rather than a decision. It matters more now
# than it did — this strategy is what dating trusts to say a person is real.

      uid { raw_info["sub"] || raw_info["userId"] }

      info do
        {
          email: raw_info["email"],
          name: raw_info["name"],
          phone: raw_info["phone_number"] || raw_info["phoneNumber"],
        }
      end

      def raw_info
        @raw_info ||= access_token.get("/vipps-userinfo-api/userinfo").parsed || {}
      rescue StandardError => e
        begin
          Master::Ground::Swallow.log(e, context: __FILE__)
        rescue StandardError
          # logging must not mask userinfo failure
        end
        @raw_info = {}
      end
    end
  end
end
