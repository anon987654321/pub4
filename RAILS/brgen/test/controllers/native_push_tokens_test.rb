# frozen_string_literal: true

require "test_helper"

class NativePushTokensTest < ActionDispatch::IntegrationTest
  TOKEN = "ab" * 32

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @user = sign_up("push")
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the shell's token is saved for the reader, downcased" do
    post native_push_tokens_path, params: { token: TOKEN.upcase, environment: "sandbox" }, as: :json
    assert_response :created
    record = NativePushToken.find_by!(token: TOKEN)
    assert_equal @user.id, record.user_id
    assert_equal "sandbox", record.environment
  end

  test "a token held by another account moves to the reader" do
    other = sign_up("other")
    NativePushToken.create!(user: other, token: TOKEN)

    post native_push_tokens_path, params: { token: TOKEN }, as: :json
    assert_response :created
    assert_equal 1, NativePushToken.where(token: TOKEN).count
    assert_equal @user.id, NativePushToken.find_by!(token: TOKEN).user_id
  end

  test "a malformed token or unknown environment is refused" do
    post native_push_tokens_path, params: { token: "not-a-token" }, as: :json
    assert_response :unprocessable_entity
    post native_push_tokens_path, params: { token: TOKEN, environment: "beta" }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, NativePushToken.count
  end

  test "destroy removes only the reader's own token" do
    other = sign_up("keeper")
    NativePushToken.create!(user: other, token: TOKEN)

    delete native_push_token_path(TOKEN)
    assert_response :ok
    assert NativePushToken.exists?(token: TOKEN)
  end

  test "nothing is sent through APNs until it is configured" do
    refute Apns.configured?
    notification = Notification.create!(user: @user, kind: "alert", title: "Saved search", body: "hit")
    NativePushToken.create!(user: @user, token: TOKEN)
    assert_nil NativePushJob.perform_now(notification.id)
  end

  private

  def sign_up(label)
    User.strict_loading(false).create!(
      email_address: "#{label}-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", username: "#{label}_#{SecureRandom.hex(3)}", city: @city
    )
  end
end
