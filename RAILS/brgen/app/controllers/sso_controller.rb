# frozen_string_literal: true

class SsoController < ApplicationController
  include Shared::SsoConsume
  allow_unauthenticated_access only: :from_master

  private

  def find_or_create_sso_user(email:, display_name:)
    user = User.find_by(email: email.to_s.downcase.strip)
    return user if user

    password = SecureRandom.hex(24)
    attrs = { email: email.to_s.downcase.strip, password: password, password_confirmation: password }
    attrs[:display_name] = display_name if display_name.present? && User.column_names.include?("display_name")
    attrs[:name] = display_name if display_name.present? && User.column_names.include?("name")
    User.create!(attrs)
  rescue StandardError => e
    Rails.logger.warn("SSO create user failed: #{e.message}")
    nil
  end

  def start_sso_session!(user)
    if respond_to?(:start_new_session_for, true)
      start_new_session_for(user)
    elsif defined?(Session)
      session_record = Session.create!(user: user)
      cookies.signed.permanent[:session_id] = { value: session_record.id, httponly: true, same_site: :lax }
    end
  end
end
