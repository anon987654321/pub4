# frozen_string_literal: true
require "omniauth-oauth2"
require_relative "../bankid_oidc"

module OmniAuth
  module Strategies
    class Bankid < OmniAuth::Strategies::OAuth2
      option :name, "bankid"
      option :environment, "production"
      option :scope, "openid profile"
      option :pkce, true

      def client
        discovery = Shared::BankidOIDC.configuration(options.environment)
        authorization = URI(discovery.fetch("authorization_endpoint"))
        token = URI(discovery.fetch("token_endpoint"))
        unless authorization.host == token.host && authorization.scheme == "https" && token.scheme == "https"
          raise Shared::BankidOIDC::InvalidToken, "BankID endpoints disagree"
        end
        ::OAuth2::Client.new(options.client_id, options.client_secret,
          site: "#{authorization.scheme}://#{authorization.host}",
          authorize_url: authorization.path, token_url: token.path, auth_scheme: :basic_auth,
          connection_opts: { request: { open_timeout: 5, timeout: 10 }, ssl: { verify: true } })
      end

      def authorize_params
        params = super
        session["bankid.nonce"] = nonce = SecureRandom.hex(32)
        params.merge(nonce:, scope: "openid profile", acr_values: "urn:bankid:bid", api_version: "4")
      end

      def callback_phase
        super
      rescue Shared::BankidOIDC::InvalidToken => error
        fail!(:invalid_credentials, error)
      end

      def build_access_token
        token = super
        raw = token.params["id_token"] || token.params[:id_token]
        @verified_claims = Shared::BankidOIDC.verify_id_token!(
          raw, environment: options.environment, client_id: options.client_id,
          nonce: session.delete("bankid.nonce"))
        token
      end

      uid { verified_claims.fetch("sub") }

      info do
        claims = verified_claims
        { name: claims["name"].presence || [claims["given_name"], claims["family_name"]].compact.join(" ").presence,
          email: nil }
      end

      extra { { id_info: verified_claims.slice("iss", "sub", "acr", "amr") } }

      private

      def verified_claims
        @verified_claims || raise(Shared::BankidOIDC::InvalidToken, "BankID identity token was not verified")
      end
    end
  end
end
