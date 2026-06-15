# frozen_string_literal: true

class NotificationPreferencesController < ApplicationController
  before_action :require_real_user

  def update
    Current.user.update!(notification_preferences_params)
    redirect_back fallback_location: root_path, notice: "Notification preferences saved."
  end

  private

  def notification_preferences_params
    params.require(:user).permit(:mention_notification_delivery)
  end
end
