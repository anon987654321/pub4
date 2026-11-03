# frozen_string_literal: true

require "test_helper"

# Shortcodes are converted where text is drawn, not where it is stored: the
# post keeps what its author typed, and every reader sees the emoji.
class EmojiShortcodeRenderTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "emoji-author@brgen.no", password: "password123",
                                                 city: @city)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a post's shortcodes read as emoji and its stored text keeps them" do
    post = ActsAsTenant.with_tenant(@city) do
      Post.create!(user: @author, city: @city, title: "Konsert", content: "<p>Bra kveld :fire: :tada: kl. 10:30:00</p>")
    end

    host! "brgen.no"
    get post_path(post)

    assert_response :success
    assert_includes response.body, "Bra kveld 🔥 🎉 kl. 10:30:00"
    assert_includes post.reload.content, ":fire:"
  end
end
