# frozen_string_literal: true

require "rack/utils"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      reject_unauthorized_connection unless cable_authenticated?
    end

    private

    def cable_authenticated?
      tok = MasterWebToken.read
      return true if tok.empty?

      candidate = cable_token_candidate
      !candidate.empty? && Rack::Utils.secure_compare(candidate, tok)
    end

    def cable_token_candidate
      cookie = cookies["master_session"].to_s
      return cookie unless cookie.empty?

      query = request.params["token"].to_s
      return query unless query.empty?

      request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "")
    end
  end
end
