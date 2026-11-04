# frozen_string_literal: true

# The engine's inbox, grouped. Shared::NotificationsController owns update,
# read_all's marking and the badge; brgen adds the kind-grouped state its index
# and read_all stream render, and asks for a real account rather than a guest.
class NotificationsController < Shared::NotificationsController
  skip_before_action :require_current_user
  before_action :require_real_user

  GROUP_ORDER = %w[mention match message reply like reaction follow order alert custom].freeze
  PER_PAGE = 100

  def index
    load_notification_index_state
  end

  def read_all
    notification_scope.unread.update_all(read_at: Time.current, updated_at: Time.current)
    Notification.broadcast_unread_badge(Current.user.id)
    load_notification_index_state
    respond_to do |format|
      format.html { redirect_to notifications_path }
      format.turbo_stream
    end
  end

  # The grouped inbox re-renders rather than dropping one row, so a group whose
  # last notification was dismissed loses its heading and the count follows.
  # The finder is the reader's own notifications, spelled out here rather than
  # through notification_scope, so the ownership guard is visible where the
  # row is deleted.
  def destroy
    Current.user.notifications.find(params[:id]).destroy!
    load_notification_index_state
    respond_to do |format|
      format.html { redirect_to notifications_path }
      format.turbo_stream { render :read_all }
    end
  end

  # The title link comes through here, so a notification someone has followed
  # stops counting as unread. Somewhere this site's own, or its vertical
  # subdomains (a match lives on dating.), and the inbox otherwise.
  def open
    notification = Current.user.notifications.find(params[:id])
    unless notification.read?
      notification.mark_as_read!
      Notification.broadcast_unread_badge(Current.user.id)
    end
    href = helpers.notification_href(notification)
    return redirect_to(notifications_path) unless own_site?(href)

    redirect_to href, allow_other_host: true
  end

  private

  def own_site?(href)
    return false if href.blank?

    host = URI.parse(href).host
    host.nil? || host == request.host || host.end_with?(".#{request.domain}")
  rescue URI::InvalidURIError
    false
  end

  def load_notification_index_state
    # A hundred a page, and the pager past them: a hard limit(100) dropped
    # everything older without a word.
    @pagy, @notifications = pagy(notification_scope.recent.includes(:actor, :notifiable), limit: PER_PAGE)
    @unread_count = notification_scope.unread.count
    @grouped_notifications = @notifications.group_by { |notification| notification.kind.to_s }
    @group_order = GROUP_ORDER
    # Grouped by kind hides what happened last; ?view=all lists it newest first.
    @view = params[:view] == "all" ? "all" : "grouped"
    @list_partial = @view == "all" ? "notifications/chronological_list" : "notifications/grouped_list"
  end
end
