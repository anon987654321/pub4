# frozen_string_literal: true

require "test_helper"

# /api sells law API keys; /api/key shows a new one once. Stripe is held still
# by swapping the two Shared::StripeBilling calls these actions make.
class ApiControllerTest < ActionDispatch::IntegrationTest
  def with_stripe(name, replacement)
    original = Shared::StripeBilling.method(name)
    Shared::StripeBilling.define_singleton_method(name, &replacement)
    yield
  ensure
    Shared::StripeBilling.define_singleton_method(name, original)
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |name| [name, ENV[name]] }
    pairs.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end

  def checkout_session(id)
    { "id" => id, "status" => "complete", "customer_details" => { "email" => "buyer@example.com" },
      "subscription" => { "id" => "sub_#{id}", "status" => "active", "customer" => "cus_#{id}",
                          "metadata" => { "plan" => "master_api_team" } } }
  end

  test "show prices each plan in its own currency, cents included" do
    get api_path

    assert_response :success
    Shared::BillingPlan.for_app("master").each do |plan|
      price = "#{plan.currency} #{format('%.2f', plan.amount / 100.0)}"
      assert_select "section[aria-labelledby='plan-#{plan.key}'] strong", text: price
    end
  end

  test "show builds its curl examples from this host's API routes" do
    host! "api.example.test"
    get api_path

    assert_includes response.body, "curl http://api.example.test/api/v1/lint"
    assert_includes response.body, "curl http://api.example.test/api/v1/copy-review"
    refute_includes response.body, "ai.brgen.no"
  end

  test "show may be cached and kept in the back-forward cache" do
    get api_path

    refute_includes response.headers["Cache-Control"].to_s, "no-store"
    assert_includes response.headers["Cache-Control"].to_s, "private"
  end

  test "an unavailable plan returns to the page with an alert that is not stored" do
    post api_checkout_path, params: { plan: "no_such_plan" }
    assert_redirected_to api_path

    follow_redirect!
    assert_select "p[role='alert']", text: I18n.t("api.unavailable")
    assert_includes response.headers["Cache-Control"].to_s, "no-store"
  end

  test "an available plan is sent to Stripe Checkout with a return to the key page" do
    captured = nil
    with_env("STRIPE_SECRET_KEY" => "sk_test", "STRIPE_WEBHOOK_SECRET" => "whsec_test",
             "STRIPE_PRICE_MASTER_API_TEAM" => "price_team") do
      with_stripe(:subscription_checkout_url, lambda { |plan:, returns: {}, **|
        captured = returns.merge(plan: plan.key)
        "https://checkout.stripe.test/pay"
      }) do
        post api_checkout_path, params: { plan: "master_api_team" }
      end
    end

    assert_redirected_to "https://checkout.stripe.test/pay"
    assert_equal "master_api_team", captured[:plan]
    assert_equal "#{api_key_url}?session_id={CHECKOUT_SESSION_ID}", captured[:success_url]
  end

  test "the key page refuses a malformed session id" do
    get api_key_path, params: { session_id: "nope" }

    assert_redirected_to api_path
  end

  test "the key page shows a new key once, with a copy button, and never again" do
    build = method(:checkout_session)

    with_stripe(:completed_checkout, ->(id) { build.call(id) }) do
      get api_key_path, params: { session_id: "cs_test_once1234" }
      assert_response :success
      assert_includes response.headers["Cache-Control"].to_s, "no-store"
      token = css_select("code#api-token").first&.text.to_s
      assert token.start_with?(ApiKey::PREFIX), "the new key is shown"
      assert_select "button[data-copy-target='api-token'][hidden]", text: I18n.t("api.copy_key")
      assert_select "script[src*='/assets/api_key_copy-'][nonce]"

      get api_key_path, params: { session_id: "cs_test_once1234" }
      assert_response :success
      assert_select "code#api-token", count: 0
      refute_includes response.body, token
    end
  end

  test "an unconfirmed checkout returns to the page" do
    with_stripe(:completed_checkout, ->(_id) { raise Shared::StripeBilling::Error, "open" }) do
      get api_key_path, params: { session_id: "cs_test_open1234" }
    end

    assert_redirected_to api_path
  end

  test "the API pages use native landmarks and the digested stylesheet" do
    get api_path

    assert_select "header.master-titlebar:not([role])"
    assert_select "main#main-content:not([role])"
    assert_select "link[rel='stylesheet'][href*='/assets/face-']"
  end

  test "the API page follows Accept-Language and varies on it" do
    get api_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }

    assert_select "html[lang='en']"
    assert_select "h1", text: I18n.t("api.heading", locale: :en)
    assert_includes response.headers["Vary"].to_s, "Accept-Language"
  end
end
