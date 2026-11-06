# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Swaps VippsClient's HTTP core for path-keyed canned answers — the one
# network seam, no gems. `vipps_real_mode!` turns VIPPS_MOCK off, grants the
# ENV credentials and records every call; the mock-mode tests simply never
# call it. Always paired with `vipps_restore_http!` in teardown.
module VippsHttpStubbing
  def vipps_real_mode!(remote_state: "AUTHORIZED")
    ENV["VIPPS_MOCK"] = "0"
    ENV["VIPPS_CLIENT_ID"] = "vip-cid"
    ENV["VIPPS_CLIENT_SECRET"] = "vip-secret"
    ENV["VIPPS_SUBSCRIPTION_KEY"] = "vip-sub"
    ENV["VIPPS_MSN"] = "123456"
    VippsClient.instance_variable_set(:@calls, [])

    sc = VippsClient.singleton_class
    sc.send(:alias_method, :orig_perform_request, :perform_request)
    sc.send(:define_method, :perform_request) do |request_class, path, headers, body|
      calls = VippsClient.instance_variable_get(:@calls) || []
      calls << {
        method: request_class.name.split("::").last,
        path: path,
        headers: headers,
        body: body,
        body_parsed: body.is_a?(String) && body.start_with?("{") ? JSON.parse(body) : body
      }
      VippsClient.instance_variable_set(:@calls, calls)

      if path == "/accesstoken/get"
        { "access_token" => "Tok1", "expires_in" => 3600 }
      elsif path.end_with?("/capture")
        { "captureId" => "cap-1" }
      elsif path.include?("/access/oauth2/token")
        { "access_token" => "Tok1", "id_token" => "id-1", "expires_in" => 3600 }
      elsif path.end_with?("/userinfo")
        { "sub" => "user-1", "name" => "Ola Nordmann", "phone_number" => "4790000004",
          "email" => "ola@example.no",
          "address" => { "street_address" => "Nygårdsgaten 12", "postal_code" => "5015",
                         "locality" => "Bergen", "formatted" => "Nygårdsgaten 12, 5015 Bergen" } }
      elsif path.end_with?("/payments") || path.include?("/payments/")
        { "reference" => "mrdamascy-tok-vipps-1", "paymentRedirectUrl" => "https://vipps.co/x1",
          "state" => remote_state }
      else
        raise "unexpected path in stub: #{path}"
      end
    end
  end

  def vipps_restore_http!
    sc = VippsClient.singleton_class
    if sc.method_defined?(:orig_perform_request)
      sc.send(:alias_method, :perform_request, :orig_perform_request)
      sc.send(:remove_method, :orig_perform_request)
    end
    VippsClient.instance_variable_set(:@access_token, nil)
    VippsClient.instance_variable_set(:@access_token_expires_at, nil)
    VippsClient.instance_variable_set(:@calls, nil)
    %w[VIPPS_MOCK VIPPS_CLIENT_ID VIPPS_CLIENT_SECRET VIPPS_SUBSCRIPTION_KEY VIPPS_MSN].each do |key|
      ENV.delete(key)
    end
  end

  def vipps_calls
    VippsClient.instance_variable_get(:@calls) || []
  end

  def vipps_call_for(path)
    call = vipps_calls.find { |c| c[:path] == path }
    assert call, "expected an HTTP call to #{path}, got: #{vipps_calls.map { |c| c[:path] }.inspect}"
    call
  end

  def vipps_reset_token_cache!
    VippsClient.instance_variable_set(:@access_token, nil)
    VippsClient.instance_variable_set(:@access_token_expires_at, nil)
  end
end

# Same seam discipline for StripeClient (second payment lane): swap the HTTP
# core for path-keyed canned answers. `stripe_real_mode!` turns STRIPE_MOCK
# off, grants the ENV credentials and records every call; mock-mode tests
# simply never call it. Always paired with `stripe_restore_http!`.
module StripeHttpStubbing
  def stripe_real_mode!(remote_status: "paid")
    ENV["STRIPE_MOCK"] = "0"
    ENV["STRIPE_SECRET_KEY"] = "sk_test_stripe"
    ENV["STRIPE_API_BASE"] = "https://api.stripe.test"
    StripeClient.instance_variable_set(:@calls, [])

    sc = StripeClient.singleton_class
    sc.send(:alias_method, :orig_perform_request, :perform_request)
    sc.send(:define_method, :perform_request) do |request_class, path, headers, body|
      calls = StripeClient.instance_variable_get(:@calls) || []
      calls << {
        method: request_class.name.split("::").last,
        path: path,
        headers: headers,
        body: body,
        body_parsed: body.is_a?(String) ? URI.decode_www_form(body).to_h : body
      }
      StripeClient.instance_variable_set(:@calls, calls)

      if path == "/v1/checkout/sessions"
        { "id" => "cs_test_123", "url" => "https://checkout.stripe.com/c/pay/cs_test_123",
          "payment_status" => "unpaid" }
      elsif path.start_with?("/v1/checkout/sessions/")
        { "id" => "cs_test_123", "payment_status" => remote_status }
      else
        raise "unexpected path in stub: #{path}"
      end
    end
  end

  def stripe_restore_http!
    sc = StripeClient.singleton_class
    if sc.method_defined?(:orig_perform_request)
      sc.send(:alias_method, :perform_request, :orig_perform_request)
      sc.send(:remove_method, :orig_perform_request)
    end
    StripeClient.instance_variable_set(:@calls, nil)
    %w[STRIPE_MOCK STRIPE_SECRET_KEY STRIPE_API_BASE STRIPE_WEBHOOK_SECRET].each do |key|
      ENV.delete(key)
    end
  end

  def stripe_calls
    StripeClient.instance_variable_get(:@calls) || []
  end

  def stripe_call_for(path)
    call = stripe_calls.find { |c| c[:path] == path }
    assert call, "expected an HTTP call to #{path}, got: #{stripe_calls.map { |c| c[:path] }.inspect}"
    call
  end

  # A valid Stripe-Signature header for a payload, keyed by webhook secret.
  def stripe_signature_for(payload, secret: "whsec_test", timestamp: Time.current.to_i)
    "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload}")}"
  end
end

module ActiveSupport
  class TestCase
    # No fixtures — every test seeds its own minimal world inline with create!
    # and rolls back per test via Rails' transactional tests.
    self.use_instantiated_fixtures = false
    self.use_transactional_tests = true

    parallelize(workers: :number_of_processors)

    include VippsHttpStubbing
    include StripeHttpStubbing

    # The sign-in rate limit counts in Rails.cache (a memory store here); a
    # count left by one test would lock the next test's sign_in out.
    setup { Rails.cache.clear }

    # The seeds' dish photos, so a seeded dish carries its photo as in db/seeds.rb.
    SEEDED_PHOTOS = YAML.load_file(Rails.root.join("db/food_photos.yml")).freeze

    # users.role enum (APP_SPEC §4): customer:0 staff:1 courier:2 admin:3
    ROLES = { customer: 0, staff: 1, courier: 2, admin: 3 }.freeze

    # ------------------------------------------------------------------
    # Auth helpers — the same contract as SessionsController#create:
    # a plain Session row + the token cookie (cookies[:session_token]).
    # ------------------------------------------------------------------
    def sign_in(user)
      # Drive the app's real phone + mock-OTP sign-in (POST /session) so the
      # session cookie is exactly what SessionsController#create sets — a
      # SIGNED cookie. Writing a plain cookie here made every controller see a
      # guest: carts keyed on user_id vanished, the reorder card never
      # rendered, staff pages bounced.
      post session_request_code_url, params: { phone: user.phone }
      post session_url, params: { phone: user.phone, code: "1234", name: user.name }
      raise "sign-in failed for #{user.phone} (#{response.status})" unless User.exists?(user.id)
      user
    end

    def sign_out
      delete session_url
    end

    def customer_sign_in(name: "Ola Nordmann", phone: "90000004")
      sign_in(User.create!(phone: phone, name: name, role: ROLES.fetch(:customer)))
    end

    def staff_sign_in
      sign_in(User.create!(phone: "90000002", name: "Umm Yusuf", role: ROLES.fetch(:staff))).tap do |user|
        user.update!(role: ROLES.fetch(:staff))
      end
    end

    def courier_sign_in
      sign_in(User.create!(phone: "90000003", name: "Kader", role: ROLES.fetch(:courier))).tap do |user|
        user.update!(role: ROLES.fetch(:courier))
      end
    end

    def seed_customer!(name: "Gjest")
      phone = "9#{SecureRandom.random_number(10_000_000).to_s.rjust(7, "0")}"
      User.create!(phone: phone, name: name, role: ROLES.fetch(:customer))
    end

    # ------------------------------------------------------------------
    # Seed helpers — minimal inline world builders (money in øre).
    # ------------------------------------------------------------------
    def seed_kitchen!
      # Idempotent on slug: setup blocks often call seed_kitchen! and then a
      # helper like seed_order! that seeds the kitchen again — the second
      # create! would violate the unique slug and fail every such test.
      Kitchen.find_or_create_by!(slug: "bergen") do |k|
        k.name = "Mr. Damascy — Danmarksplass"
        k.address = "Solheimsgaten 60, 5054 Bergen"
        k.postcode = "5054"
        k.phone = "955 55 600"
        k.opening_hours = "Man–Fre 11–21 · Lør–Søn 14–21"
        k.opening_hours_en = "Mon–Fri 11am–9pm · Sat–Sun 2pm–9pm"
        k.rating = 4.9
      end
    end

    def seed_zone!(postcode: "5004", name: "Strandgaten", fee_ore: 2900,
                   min_basket_ore: 15000, eta_minutes: 20)
      DeliveryZone.create!(
        postcode: postcode,
        name: name,
        fee_ore: fee_ore,
        min_basket_ore: min_basket_ore,
        eta_minutes: eta_minutes
      )
    end

    def seed_category!(kitchen, name: "Wraps & Ruller", slug: "wraps", emoji: "🌯", position: 1)
      MenuCategory.create!(
        kitchen: kitchen,
        name: name,
        name_en: "Wraps & Rolls",
        slug: slug,
        emoji: emoji,
        position: position
      )
    end

    def seed_item!(category, name: "Damaskus Kylling Shawarma",
                   name_en: "Damascus Chicken Shawarma",
                   description: "Kylling, toum og sylteagurk i gjæret brød.",
                   price_ore: 12900, origin: "damaskus", emoji: "🌯", heat: 1,
                   badges: "signature", weight_g: 450, position: 1, available: true)
      MenuItem.create!(
        menu_category: category,
        name: name,
        name_en: name_en,
        description: description,
        description_en: description,
        price_ore: price_ore,
        origin: origin,
        emoji: emoji,
        heat: heat,
        badges: badges,
        weight_g: weight_g,
        position: position,
        available:, photo_path: SEEDED_PHOTOS[name]
      )
    end

    def seed_option!(item, name: "Toum", kind: "sauce", price_ore: 0,
                     default_on: false, position: 1)
      ItemOption.create!(
        menu_item: item,
        name: name,
        name_en: name,
        price_ore: price_ore,
        kind: kind,
        default_on: default_on,
        position: position
      )
    end

    def seed_promo!(code:, kind:, value:, min_basket_ore: 0, active: true, description: "Test-rabatt")
      PromoCode.create!(
        code: code,
        kind: kind,
        value: value,
        min_basket_ore: min_basket_ore,
        active: active,
        description: description
      )
    end

    # A minimal open order for staff/courier/track tests. Tracking token is
    # deterministic unless nil is passed explicitly (which exercises the
    # model's auto-generation).
    def seed_order!(user: nil, kitchen: nil, state: "placed", delivery_mode: "delivery",
                    token: SecureRandom.hex(10))
      kitchen ||= seed_kitchen!
      user ||= seed_customer!
      Order.create!(
        user: user,
        kitchen: kitchen,
        state: state,
        delivery_mode: delivery_mode,
        address: "Nygårdsgaten 12",
        postcode: "5004",
        phone: "90000004",
        subtotal_ore: 12900,
        delivery_fee_ore: 2900,
        discount_ore: 0,
        tip_ore: 0,
        total_ore: 15800,
        eta_minutes: 20,
        tracking_token: token,
        payment_state: "pending",
        payment_steps: 3,
        express: true,
        placed_at: Time.current
      )
    end

    # The one open cart for a signed-in identity (Cart.for(user) contract).
    def open_cart_for(user)
      Cart.find_by(user: user)
    end
  end
end
