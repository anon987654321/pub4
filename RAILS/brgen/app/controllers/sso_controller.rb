# frozen_string_literal: true

class SsoController < ApplicationController
  include Shared::SsoConsume
  include Shared::SsoUserProvisioning
  allow_unauthenticated_access only: :from_master

  private

  # brgen boots in configurations where Shared::Authentication is not mixed in,
  # so start_new_session_for may be absent; fall back to writing the Session row
  # and cookie directly rather than losing the handover.
  def start_sso_session!(user)
    return super if respond_to?(:start_new_session_for, true)
    return unless defined?(Session)

    session_record = Session.create!(user:)
    cookies.signed.permanent[:session_id] = { value: session_record.id, httponly: true, same_site: :lax, domain: :all }
  end
end
