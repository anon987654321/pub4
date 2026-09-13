# frozen_string_literal: true

# Pushes a Notification to the user's registered browsers. The payload is
# brgen's — a title, the target path and a per-kind tag — and the delivery is
# Shared::Pushable.deliver_now, the loop the messenger's pushes use too, so dead
# endpoints are pruned and credential failures raised in one place. No-ops when
# VAPID is unconfigured.
class WebPushJob < ApplicationJob
  queue_as :bulk

  def perform(notification_id)
    # Reload with the user preloaded and strict loading off — this runs in a job
    # with no request, where the belongs_to read would otherwise raise.
    notification = ::Notification.strict_loading(false).includes(:user).find_by(id: notification_id)
    user = notification&.user
    return if user.nil? || (user.respond_to?(:guest?) && user.guest?)

    Shared::Pushable.deliver_now(
      user,
      title: notification.try(:title).presence || "brgen",
      body: notification.try(:body).to_s,
      url: target_path(notification),
      tag: "brgen-#{notification.kind}"
    )
  end

  private

  # The payload url was hardcoded to "/", so tapping a push about a parcel, an
  # order or a saved-search match landed on the city home page and left the
  # reader to find the thing themselves — which is most of the value of a push
  # gone.
  #
  # Paths are built by hand rather than through url_helpers: a job has no
  # request, so it has no host, and the service worker opens a path anyway.
  # Anything unrecognised still falls back to "/" rather than guessing.
  def target_path(notification)
    id = notification.source_id
    return "/notifications" if id.blank?

    case notification.source_type
    when "Takeaway::Order"    then "/orders/#{id}"
    when "Marketplace::Order" then "/orders/#{id}"
    when "Marketplace::Listing" then "/listings/#{id}"
    when "Marketplace::SavedSearch" then "/saved_searches"
    when "Event"    then "/events/#{id}"
    when "Post"     then "/posts/#{id}"
    when "Message"  then "/conversations"
    when "Community" then "/communities/#{id}"
    else "/notifications"
    end
  end
end
