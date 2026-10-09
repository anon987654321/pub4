# frozen_string_literal: true

require "test_helper"

# These keys were read with an English `default:` and defined in neither locale,
# so a Norwegian visitor saw "Media wall", "Upvote" and "Seller centre". A key
# that exists only as a default also drifts: nobody can translate it.
class PublicChromeLocaleTest < ActiveSupport::TestCase
  KEYS = %w[
    home.media_wall_view home.feed_views home.pagination home.media_wall_add_hint
    post.new_steps post.new_continue post.new_text_only post.new_publishing
    posts.video posts.audio pwa.queued
    post.read_more post.embed post.voting post.upvote post.downvote legal.changelog
    marketplace.share_to_feed marketplace.add_to_amber marketplace.seller_center.title
    marketplace.seller_center.rating marketplace.ranking_reasons.label
    cookie_consent.purposes.necessary.title cookie_consent.purposes.necessary.body
  ].freeze

  KEYS.each do |key|
    test "#{key} is translated in nb and en" do
      %i[nb en].each do |locale|
        assert I18n.exists?(key, locale), "#{key} missing in #{locale}"
      end
      assert_not_equal I18n.t(key, locale: :en), I18n.t(key, locale: :nb), "#{key} reads the same in nb and en" unless %w[home.feed_view post.new_step_media].include?(key)
    end
  end
end
