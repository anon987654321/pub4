# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :require_real_user

  def index
    @notifications = Current.user.notifications.recent.limit(100)
  end

  def update
    notification = Current.user.notifications.find(params[:id])
    notification.update!(read_at: Time.current)
    redirect_back fallback_location: notifications_path
  end
end
