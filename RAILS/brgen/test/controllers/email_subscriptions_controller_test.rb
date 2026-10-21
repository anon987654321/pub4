# frozen_string_literal: true

require "test_helper"

class EmailSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "brgen.no" }

  test "create requires affirmative marketing consent before saving or sending mail" do
    assert_no_difference -> { EmailSubscription.count } do
      post email_subscriptions_path, params: {
        email_subscription: { email: "no-consent@example.test" }
      }
    end

    assert_redirected_to root_path
    assert_equal I18n.t("newsletter_popup.consent_required"), flash[:alert]
  end

  test "create stores affirmative consent and waits for email confirmation" do
    assert_difference -> { EmailSubscription.count }, 1 do
      post email_subscriptions_path, params: {
        email_subscription: {
          email: "consented@example.test",
          agreed_to_marketing: "1"
        }
      }
    end

    subscription = EmailSubscription.find_by!(email: "consented@example.test")
    assert subscription.agreed_to_marketing?
    refute subscription.confirmed?
    assert_redirected_to root_path
  end


  test "show renders without mutating the subscription" do
    subscription = EmailSubscription.create!(
      email: "preferences-show@example.com",
      confirmed: true,
      agreed_to_marketing: true
    )

    get email_subscription_path(token: subscription.token)

    assert_response :success
    assert_includes response.body, I18n.t("email_preferences.title")
    assert subscription.reload.agreed_to_marketing?
  end

  test "update changes marketing consent" do
    subscription = EmailSubscription.create!(
      email: "preferences-update@example.com",
      confirmed: true,
      agreed_to_marketing: true
    )

    patch email_subscription_path(token: subscription.token),
      params: { email_subscription: { marketing: "0" } }

    assert_redirected_to email_subscription_path(token: subscription.token)
    assert_not subscription.reload.agreed_to_marketing?

    patch email_subscription_path(token: subscription.token),
      params: { email_subscription: { marketing: "1" } }

    assert_redirected_to email_subscription_path(token: subscription.token)
    assert subscription.reload.agreed_to_marketing?
  end

  test "delete removes the subscription" do
    subscription = EmailSubscription.create!(email: "preferences-delete@example.com")

    delete email_subscription_path(token: subscription.token)

    assert_redirected_to root_path
    assert_not EmailSubscription.exists?(subscription.id)
  end
end
