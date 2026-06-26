# frozen_string_literal: true

module Shared
  class NotificationsController < ApplicationController
    before_action :require_current_user

    def index
      @notifications = notification_scope.recent.limit(50)
    end

    def update
      @notification = notification_scope.find(params[:id])
      @notification.mark_as_read!
      respond_to do |format|
        format.html { redirect_back fallback_location: main_app.root_path }
        format.turbo_stream
        format.json { head :no_content }
      end
    end

    def read_all
      notification_scope.unread.update_all(read_at: Time.current, updated_at: Time.current)
      @notifications = notification_scope.recent.limit(50)
      respond_to do |format|
        format.html { redirect_back fallback_location: main_app.root_path }
        format.turbo_stream
        format.json { head :no_content }
      end
    end

    def badge
      render json: { unread_count: notification_scope.unread.count }
    end

    private

    def notification_scope
      klass = defined?(::Notification) ? ::Notification : Shared::Notification
      klass.where(user: current_user)
    end

    def require_current_user
      return if respond_to?(:current_user, true) && current_user

      redirect_to main_app.root_path, alert: "Sign in required"
    end
  end
end
