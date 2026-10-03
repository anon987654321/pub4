# frozen_string_literal: true

require "minitest/autorun"
require "ostruct"
require_relative "../../app/services/shared/strunk_white_pass"
require_relative "../../app/services/shared/newsletter_composer"

class NewsletterComposerTest < Minitest::Test
  def test_daily_edition_has_godin_voice_fields
    story = OpenStruct.new(
      title: "New café on Torget",
      content: "I think that perhaps you should try the cinnamon bun.",
      community: OpenStruct.new(name: "Mat"),
      author_name: "local",
    )

    edition = Shared::NewsletterComposer.daily(
      city_name: "Bergen",
      stories: [ story ],
      app_name: "Brgen",
    )

    assert_equal "Brgen", edition.app_name
    assert_match(/Bergen/, edition.subject)
    refute_match(/perhaps/i, edition.lede)
    assert edition.permission_line.include?("subscribed")
    assert_equal 1, edition.stories.size
    refute_match(/I think that/i, edition.stories.first.teaser)
  end

  def test_weekly_deals_edition_curates_offers
    deal = OpenStruct.new(
      title: "Wool sweater",
      click_url: "https://example.com/deal",
      description: "Perhaps the best price this week.",
      price: "499",
      currency: "NOK",
      merchant: "Norrøna",
      image_url: "https://example.com/img.jpg",
    )

    edition = Shared::NewsletterComposer.weekly_deals(city_name: "Bergen", deals: [ deal ])

    assert_equal :weekly_deals, edition.kind
    assert_equal 1, edition.deals.size
    refute_match(/perhaps/i, edition.deals.first.description)
  end
end
