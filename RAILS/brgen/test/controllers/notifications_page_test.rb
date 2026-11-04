# frozen_string_literal: true

require "test_helper"

# The inbox's heading, kicker and cards, and the partial its read reflex
# morphs in: the h1 is the page's name alone, the kicker names this city, each
# card has one link to where it leads, and the reflex redraws the inbox's card.
class NotificationsPageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @user = User.strict_loading(false).create!(
      email_address: "np-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "np_#{SecureRandom.hex(3)}", city: @city
    )
    @actor = User.strict_loading(false).create!(
      email_address: "np-actor-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "np_actor_#{SecureRandom.hex(3)}", city: @city
    )
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the heading is the page's name, with the unread count beside it" do
    Notification.create!(user: @user, actor: @actor, kind: "follow")

    get notifications_path

    assert_select "h1", text: I18n.t("notifications.title", locale: :nb)
    assert_select "h1 .badge", count: 0
    assert_select "hgroup p[role='status'] .badge", text: I18n.t("notifications.unread_count", count: 1, locale: :nb)
  end

  test "the kicker names the city the inbox is in" do
    get notifications_path

    assert_select "hgroup p", text: "#{@city.name}-innboks"
  end

  test "groups use semantic names and a card links once to where it leads" do
    Notification.create!(user: @user, actor: @actor, kind: "follow")

    get notifications_path

    assert_select "section.notification-group > h2"
    assert_select "section.mb-12, h2.section-heading--md", count: 0
    card = css_select("article.notification-card").first
    assert card
    links = card.css("a").map { |link| link["href"] }
    assert_equal links.uniq, links
  end

  test "following a notification's title marks it read and lands where it leads" do
    notification = Notification.create!(user: @user, actor: @actor, kind: "follow")

    get notifications_path
    assert_select "article##{ActionView::RecordIdentifier.dom_id(notification)} a.notification-title-link[href=?]",
                  open_notification_path(notification)

    get open_notification_path(notification)
    assert_redirected_to user_path(@actor)
    assert notification.reload.read?
  end

  test "nobody opens another reader's notification" do
    theirs = Notification.create!(user: @actor, actor: @user, kind: "follow")

    get open_notification_path(theirs)
    assert_response :not_found
    refute theirs.reload.read?
  end

  test "the read reflex morphs the inbox's own card" do
    notification = Notification.create!(user: @user, actor: @actor, kind: "follow")
    html = ApplicationController.render(partial: Shared::NotificationReadReflex::PARTIAL, locals: { notification: })

    assert_includes html, %(id="#{ActionView::RecordIdentifier.dom_id(notification)}")
    refute Rails.root.join("app/views/notifications/_notification_row.html.erb").exist?
  end
end
