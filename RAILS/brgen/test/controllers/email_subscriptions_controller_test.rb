# frozen_string_literal: true

require "test_helper"

class EmailSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "brgen.no" }

  test "create requires affirmative marketing consent before saving or sending mail" do
    assert_no_difference -> { EmailSubscription.count } do
      post email_subscriptions_path, params: {
        email_subscription: { email: "no-consent@example.test" },
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
          agreed_to_marketing: "1",
        },
      }
    end

    subscription = EmailSubscription.find_by!(email: "consented@example.test")
    assert subscription.agreed_to_marketing?
    refute subscription.confirmed?
    event = Shared::AuditEvent.where(
      target_type: "EmailSubscription", target_id: subscription.id,
      action: "newsletter.marketing_consent.granted"
    ).order(:occurred_at).last
    assert event
    assert_equal "signup_form", event.metadata["source"]
    assert_equal EmailSubscription::MARKETING_CONSENT_VERSION, event.metadata["consent_version"]
    assert_not_nil event.occurred_at
    assert_redirected_to root_path
  end

  test "public re-consent rotates the confirmation token and requires inbox confirmation" do
    subscription = EmailSubscription.create!(
      email: "reconsent@example.test",
      confirmed: true,
      confirmed_at: Time.current,
      agreed_to_marketing: false
    )
    previous_token = subscription.token

    # The confirmation job runs inline (ApplicationJob.run_inline!), so the mail is the evidence.
    assert_emails 1 do
      post email_subscriptions_path, params: {
        email_subscription: {
          email: subscription.email,
          agreed_to_marketing: "1",
        },
      }
    end

    subscription.reload
    assert subscription.agreed_to_marketing?
    refute subscription.confirmed?
    assert_nil subscription.confirmed_at
    refute_equal previous_token, subscription.token
    event = Shared::AuditEvent.where(
      target_type: "EmailSubscription", target_id: subscription.id,
      action: "newsletter.marketing_consent.granted"
    ).order(:occurred_at).last
    assert event
    assert_equal "signup_form", event.metadata["source"]
    assert_equal EmailSubscription::MARKETING_CONSENT_VERSION, event.metadata["consent_version"]
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
    refute subscription.reload.agreed_to_marketing?
    revoke = Shared::AuditEvent.where(
      target_type: "EmailSubscription", target_id: subscription.id,
      action: "newsletter.marketing_consent.revoked"
    ).order(:occurred_at).last
    assert revoke
    assert_equal "preference_center", revoke.metadata["source"]

    patch email_subscription_path(token: subscription.token),
      params: { email_subscription: { marketing: "1" } }

    assert_redirected_to email_subscription_path(token: subscription.token)
    assert subscription.reload.agreed_to_marketing?
    grant = Shared::AuditEvent.where(
      target_type: "EmailSubscription", target_id: subscription.id,
      action: "newsletter.marketing_consent.granted"
    ).order(:occurred_at).last
    assert grant
    assert_equal "preference_center", grant.metadata["source"]
    assert_equal EmailSubscription::MARKETING_CONSENT_VERSION, grant.metadata["consent_version"]
  end

  test "delete removes the subscription" do
    subscription = EmailSubscription.create!(email: "preferences-delete@example.com")

    delete email_subscription_path(token: subscription.token)

    assert_redirected_to root_path
    assert_not EmailSubscription.exists?(subscription.id)
  end

  # The mail client posts this body with no session and no CSRF token.
  test "one-click stops marketing mail and keeps the consent trail" do
    subscription = EmailSubscription.create!(
      email: "one-click@example.com", confirmed: true, agreed_to_marketing: true
    )

    post one_click_email_subscription_path(token: subscription.token),
      params: "List-Unsubscribe=One-Click", headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    assert_response :ok
    assert EmailSubscription.exists?(subscription.id)
    refute subscription.reload.agreed_to_marketing?
    revoke = Shared::AuditEvent.where(
      target_type: "EmailSubscription", target_id: subscription.id,
      action: "newsletter.marketing_consent.revoked"
    ).last
    assert_equal "one_click", revoke.metadata["source"]
  end

  test "one-click with an unknown token answers 404" do
    post one_click_email_subscription_path(token: "not-a-token")

    assert_response :not_found
  end
end
