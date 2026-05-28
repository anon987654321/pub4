# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :require_real_user

  def index
    @notifications = Current.user.notifications.recent.limit(100)
  end

  def update
    @notification = Current.user.notifications.find(params[:id])
    @notification.update!(read_at: Time.current)
    respond_to do |f|
      f.html { redirect_back fallback_location: notifications_path }
      f.turbo_stream
    end
  end

  def read_all
    Current.user.notifications.unread.update_all(read_at: Time.current)
    respond_to do |f|
      f.html { redirect_to notifications_path }
      f.turbo_stream
    end
  end
end
