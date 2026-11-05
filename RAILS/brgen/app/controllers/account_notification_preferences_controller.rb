# frozen_string_literal: true

# The account page's push-and-email choices per kind of notification.
class AccountNotificationPreferencesController < ApplicationController
  before_action :require_user_session
  rate_limit to: 20, within: 10.minutes, only: :update, name: "account_notifications",
             by: -> { "u#{Current.user&.id}" }

  def update
    Current.user.update_notification_preferences!(params.fetch(:preferences, {}).to_unsafe_h)
    redirect_to account_path, notice: t("account_notifications.saved")
  end
end
