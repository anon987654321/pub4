# frozen_string_literal: true

require "test_helper"

# A post body is stored as HTML. The feed card printed it escaped, so the
# 2026-11-03 screenshot sweep showed a literal "<p>Regnjakke-uke..." in the
# feed; the card now renders it through rich_text, the same allowlist the
# show page uses.
class PostCardBodyTest < ActionDispatch::IntegrationTest
  def test_feed_card_renders_body_markup_and_drops_what_the_allowlist_refuses
    post posts_url, params: { post: { body: "<p>Regnjakke-uke i <strong>Bergen</strong><script>alert(1)</script></p>",
                                      anonymous: true } }

    get posts_url

    assert_response :success
    refute_includes response.body, "&lt;p&gt;Regnjakke"
    assert_select ".feed-card-body p", text: /Regnjakke-uke i Bergen/
    assert_select ".feed-card-body strong", "Bergen"
    assert_select ".feed-card-body script", count: 0
  end
end
