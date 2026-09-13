# frozen_string_literal: true

# The engine's inbox, grouped. Shared::NotificationsController owns update,
# read_all's marking and the badge; brgen adds the kind-grouped state its index
# and read_all stream render, and asks for a real account rather than a guest.
class NotificationsController < Shared::NotificationsController
  skip_before_action :require_current_user
  before_action :require_real_user

  GROUP_ORDER = %w[mention match message reply like reaction follow order alert custom].freeze

  def index
    load_notification_index_state
  end

  def read_all
    notification_scope.unread.update_all(read_at: Time.current, updated_at: Time.current)
    load_notification_index_state
    respond_to do |format|
      format.html { redirect_to notifications_path }
      format.turbo_stream
    end
  end

  private

  def load_notification_index_state
    @notifications = notification_scope.recent.includes(:actor, :notifiable).limit(100)
    @unread_count = notification_scope.unread.count
    @grouped_notifications = @notifications.group_by { |notification| notification.kind.to_s }
    @group_order = GROUP_ORDER
  end
end
