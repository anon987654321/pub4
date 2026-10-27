# frozen_string_literal: true

require "minitest/autorun"

class SharedRegistrationContractTest < Minitest::Test
ROOT = File.expand_path("../..", __dir__)

# brgen and amber side by side exist only in the repo checkout. An app's CI on
# vm23 sees /home/<app>/app and __shared, so there this contract has nothing
# to compare and is skipped rather than failing on ENOENT.
def setup
  skip "brgen and amber are not beside __shared in this layout" unless
    %w[brgen amber].all? { |app| File.directory?(File.join(ROOT, app, "app")) }
end

  def test_brgen_and_amber_render_the_same_registration_fields
    shared_fields = File.read(File.join(ROOT, "__shared/app/views/shared/_registration_fields.html.erb"))
    brgen_view = File.read(File.join(ROOT, "brgen/app/views/users/new.html.erb"))
    amber_view = File.read(File.join(ROOT, "amber/app/views/registrations/new.html.erb"))

    assert_includes brgen_view, %(render "shared/registration_fields", form: f, include_username: true)
    assert_includes amber_view, %(render "shared/registration_fields", form: f)
    assert_includes shared_fields, "password_confirmation"
    assert_includes shared_fields, "accept_age"
    assert_includes shared_fields, "accept_terms"
    refute_includes shared_fields, "agreed_to_marketing"
  end

  def test_brgen_and_amber_share_email_registration_and_verification
    brgen_controller = File.read(File.join(ROOT, "brgen/app/controllers/users_controller.rb"))
    amber_controller = File.read(File.join(ROOT, "amber/app/controllers/registrations_controller.rb"))
    verification = File.read(File.join(ROOT, "__shared/app/controllers/concerns/shared/email_verification_actions.rb"))
    auth = File.read(File.join(ROOT, "__shared/app/controllers/concerns/shared/authentication.rb"))

    assert_includes brgen_controller, "include Shared::EmailRegistration"
    assert_includes amber_controller, "include Shared::EmailRegistration"
    assert_includes brgen_controller, "send_signup_verification!(@user)"
    assert_includes amber_controller, "send_signup_verification!(@user)"
    assert_includes verification, "verify_email_token!(token)"
    assert_match(/user\.try\(:guest\?\).*email_verified\?/, auth)
  end

  def test_guest_post_and_chat_paths_are_not_gated_by_email_verification
    posts = File.read(File.join(ROOT, "amber/app/controllers/posts_controller.rb"))
    comments = File.read(File.join(ROOT, "amber/app/controllers/comments_controller.rb"))
    messages = File.read(File.join(ROOT, "amber/app/controllers/messages_controller.rb"))
    auth = File.read(File.join(ROOT, "__shared/app/controllers/concerns/shared/authentication.rb"))

    [posts, comments, messages].each do |source|
      assert_includes source, "before_action :require_verified_email, only: :create"
    end
    assert_match(/user\.nil\? \|\| user\.try\(:guest\?\)/, auth)
    assert File.file?(File.join(ROOT, "amber/test/controllers/posts_controller_anonymous_test.rb"))
  end
end
