# frozen_string_literal: true

require "test_helper"

# A feed card is fragment-cached until the post changes. Its relative time must
# not be cached with it, or a card says "5 minutter siden" for hours.
class PostCardTimeTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "card-time@brgen.no", password: "password123",
                                                 city: @city)
    @caching_was = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    Rails.cache.clear
  end

  teardown do
    ActionController::Base.perform_caching = @caching_was
    Rails.cache.clear
    ActsAsTenant.current_tenant = nil
  end

  def card_time(post)
    css_select("##{ActionView::RecordIdentifier.dom_id(post)} time.feed-card-time").first&.text.to_s.strip
  end

  def expected(post)
    I18n.with_locale(:nb) do
      I18n.t("shared.time_ago", time: ApplicationController.helpers.time_ago_in_words(post.created_at))
    end
  end

  test "a cached card shows the time as of this render, not the first" do
    post = ActsAsTenant.with_tenant(@city) do
      Post.create!(user: @author, city: @city, title: "Fersk", content: "Tekst")
    end
    host! "brgen.no"

    travel 5.minutes do
      get root_path
      assert_equal expected(post), card_time(post)
    end

    travel 3.hours do
      get root_path
      assert_response :success
      assert_equal expected(post), card_time(post), "the card kept the time it was cached with"
    end
  end
end
