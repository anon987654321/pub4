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

  test "a card shows who it is from, linked to them, unless they wrote as a guest" do
    @actor.update_columns(display_name: "Avsender Navn")
    named = Notification.create!(user: @user, actor: @actor, kind: "follow")
    guest = User.strict_loading(false).create!(email_address: "np-guest-#{SecureRandom.hex(3)}@brgen.no",
                                               password: "password123", guest: true, city: @city)
    anonymous = Notification.create!(user: @user, actor: guest, kind: "mention")

    get notifications_path

    actor_link = "article##{ActionView::RecordIdentifier.dom_id(named)} a.notification-actor[href=?]"
    assert_select actor_link, user_path(@actor) do
      assert_select "img[src=?][alt='']", @actor.avatar_url
      assert_select "span", text: "Avsender Navn"
    end
    assert_select "article##{ActionView::RecordIdentifier.dom_id(anonymous)} a.notification-actor", 0
  end

  test "the All view lists every kind newest first, beside the grouped default" do
    Notification.create!(user: @user, actor: @actor, kind: "follow", title: "Eldste varsel", created_at: 2.hours.ago)
    Notification.create!(user: @user, actor: @actor, kind: "mention", title: "Midterste varsel", created_at: 1.hour.ago)
    Notification.create!(user: @user, actor: @actor, kind: "follow", title: "Nyeste varsel")

    get notifications_path
    assert_select "nav.notification-views a[aria-current=page][href=?]", notifications_path
    grouped = response.body
    assert_operator grouped.index("Midterste varsel"), :<, grouped.index("Nyeste varsel"), "mentions lead by kind"

    get notifications_path(view: "all")
    assert_select "nav.notification-views a[aria-current=page][href=?]", notifications_path(view: "all")
    body = response.body
    assert_operator body.index("Nyeste varsel"), :<, body.index("Midterste varsel")
    assert_operator body.index("Midterste varsel"), :<, body.index("Eldste varsel")
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

  test "the inbox pages past its hundred newest instead of dropping the rest" do
    rows = (1..101).map do |n|
      at = n.minutes.ago
      { user_id: @user.id, kind: "custom", title: "Varsel-#{n}-slutt", created_at: at, updated_at: at }
    end
    Notification.insert_all!(rows)

    get notifications_path
    assert_select "article.notification-card", 100
    refute_includes response.body, "Varsel-101-slutt"
    assert_select "nav.pager a[rel=next][href*=?]", "page=2"

    get notifications_path(page: 2)
    assert_includes response.body, "Varsel-101-slutt"
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

  test "likes on one post and follows fold into one row each, naming the newest" do
    people = Array.new(3) do |i|
      User.strict_loading(false).create!(email_address: "np-fan#{i}-#{SecureRandom.hex(3)}@brgen.no",
                                         password: "password123", username: "np_fan#{i}_#{SecureRandom.hex(3)}",
                                         display_name: "Fan #{i}", city: @city)
    end
    post_a = Post.create!(user: @user, title: "Fjelltur", content: "Ulriken i dag", city: @city)
    post_b = Post.create!(user: @user, title: "Kaffe", content: "Beste i byen", city: @city)
    people.each_with_index do |fan, i|
      Notification.create!(user: @user, actor: fan, kind: "like", notifiable: post_a, created_at: i.minutes.from_now)
    end
    Notification.create!(user: @user, actor: people.first, kind: "like", notifiable: post_b)
    people.first(2).each_with_index do |fan, i|
      Notification.create!(user: @user, actor: fan, kind: "follow", created_at: i.minutes.from_now)
    end

    get notifications_path

    assert_select ".notification-cluster", 2
    assert_select ".notification-cluster h3", text: I18n.t("notifications.aggregate.like_post", name: "Fan 2", count: 2)
    assert_select ".notification-cluster h3", text: I18n.t("notifications.aggregate.follow", name: "Fan 1", count: 1)
    assert_select ".notification-cluster summary", text: I18n.t("notifications.aggregate.show_all", count: 3)
    assert_select ".notification-cluster details .notification-card", 5,
                  "every single row is still there behind the disclosure"
    assert_select ".notification-group > .notification-card:not(.notification-cluster)", 1,
                  "the lone like on another post stays a row"
  end
end
