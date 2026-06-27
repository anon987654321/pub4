# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :require_real_user

  def index
    load_notification_index_state
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
    load_notification_index_state
    respond_to do |f|
      f.html { redirect_to notifications_path }
      f.turbo_stream
    end
  end

  def badge
    render json: { unread_count: Current.user.notifications.unread.count }
  end

  private

  def load_notification_index_state
    @notifications = Current.user.notifications.recent.limit(100)
    @unread_count = Current.user.notifications.unread.count
    @grouped_notifications = @notifications.group_by { |notification| notification.kind.to_s }
    @group_order = %w[mention match message reply like reaction custom]
  end
end
