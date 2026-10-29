# frozen_string_literal: true

require "test_helper"

class SessionsControllerGuestTransferTest < ActionDispatch::IntegrationTest
  test "password sign-in preserves the guest session when history transfer fails" do
    post_body = "Guest post before blocked sign-in #{SecureRandom.hex(5)}"
    post posts_url, params: { post: { body: post_body, anonymous: true } }
    assert_redirected_to root_path
    guest_post = Post.find_by!(body: post_body)
    guest = User.find(guest_post.user_id)
    assert guest.guest?
    assert_equal guest.id, session[:guest_user_id]

    member = User.create!(
      email_address: "member-#{SecureRandom.hex(5)}@example.test",
      password: "long-enough-password",
      password_confirmation: "long-enough-password"
    )
    merger = Object.new
    merger.define_singleton_method(:call) do
      raise ActiveRecord::MigrationError, "simulated missing account_merges table"
    end

    AccountMerger.stub(:new, ->(**_kwargs) { merger }) do
      post session_path, params: {
        email_address: member.email_address,
        password: "long-enough-password",
      }
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("shared.flash.guest_history_transfer_failed"), flash[:alert]
    assert_equal guest.id, session[:guest_user_id], "the failed transfer must not rotate the guest session"
    assert guest.reload.guest?
    assert_equal guest.id, guest_post.reload.user_id
    refute Session.exists?(user_id: member.id), "failed transfer must not create an authenticated session"
    assert_empty AccountMerge.where(guest_user_id: guest.id, user_id: member.id)
  end
end
