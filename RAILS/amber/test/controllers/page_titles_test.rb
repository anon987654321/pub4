# frozen_string_literal: true

require "test_helper"

# posts#index, posts#feed, posts#new and users#show set no title or
# description, so all four fell back to the bare "Amber" title and the
# site-wide description.
class PageTitlesTest < ActionDispatch::IntegrationTest
  setup do
    email = "pt-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
  end

  test "the post pages and the profile name themselves" do
    pages = {
      posts_path => [ I18n.t("pages.community"), I18n.t("post.index_description") ],
      feed_posts_path => [ I18n.t("pages.feed"), I18n.t("post.feed_description") ],
      new_post_path => [ I18n.t("post.share_look"), nil ],
      user_path(@user) => [ @user.display_name, I18n.t("users.profile_description", name: @user.display_name) ],
    }

    pages.each do |path, (title, description)|
      get path
      assert_response :success, path
      assert_select "title", text: /\A#{Regexp.escape(title)}/
      assert_select "meta[name=description][content=?]", description if description
    end
  end
end
