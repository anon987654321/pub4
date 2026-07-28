# frozen_string_literal: true

module Shared
  # Identifies an ActionCable connection from the signed session cookie.
  #
  # Every app had the same connect/set_current_user pair. brgen additionally
  # accepts soft guests, so set_current_user is written to be overridden with a
  # `super` call — it returns true/false rather than the assignment's value so
  # an override can tell "found" from "keep looking".
  module CableIdentity
    extend ActiveSupport::Concern

    included do
      identified_by :current_user
    end

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private

    def set_current_user
      session_record = Session.find_by(id: cookies.signed[:session_id])
      return false unless session_record

      self.current_user = session_record.user
      true
    end
  end
end
