# frozen_string_literal: true

require "test_helper"

# Push and email per kind of notification, chosen on the account page. Push
# stays on and email off until a person changes them.
class AccountNotificationPreferencesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @user = person("varsel")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(tag)
    User.strict_loading(false).create!(email_address: "#{tag}-#{SecureRandom.hex(4)}@brgen.no",
                                       password: "password123", city: @city)
  end

  test "the account page offers push and email for each kind, with the defaults ticked" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }

    get account_path

    assert_select "form[action=?]", account_notification_preferences_path
    assert_select "input[type=checkbox][name='preferences[mention][push]'][checked]"
    assert_select "input[type=checkbox][name='preferences[mention][email]']:not([checked])"
  end

  test "saved choices turn email on and push off for a kind" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }

    patch account_notification_preferences_path, params: {
      preferences: { follow: { push: "0", email: "1" }, mention: { push: "1", email: "0" } }
    }

    @user.reload
    assert @user.notify_by?(:email, "follow")
    assert_not @user.notify_by?(:push, "follow")
    assert @user.notify_by?(:push, "mention")
    assert_not @user.notify_by?(:email, "reply"), "an unsent box is a choice: off"
  end

  test "a follow emails a person who asked for it and pushes only to those who kept push" do
    @user.update!(notification_preferences: { "follow" => { "push" => false, "email" => true } })
    follower = person("folger")

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      assert_no_enqueued_jobs only: Shared::WebPushJob do
        @user.notifications.create!(actor: follower, kind: "follow")
      end
    end

    keeper = person("standard")
    assert_no_enqueued_jobs only: ActionMailer::MailDeliveryJob do
      assert_enqueued_jobs 1, only: Shared::WebPushJob do
        keeper.notifications.create!(actor: follower, kind: "follow")
      end
    end
  end

  test "the email names what happened and links to the choices" do
    follower = person("folger")
    notification = @user.notifications.create!(actor: follower, kind: "follow")

    mail = NotificationMailer.notice(notification)

    assert_equal [ @user.email_address ], mail.to
    assert_equal notification.title, mail.subject
    assert_includes mail.text_part.body.to_s, "/account"
  end
end
