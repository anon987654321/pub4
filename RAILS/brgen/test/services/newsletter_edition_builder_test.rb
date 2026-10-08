# frozen_string_literal: true

require "test_helper"

# The builder had no test, and composed nothing in production for as long as it
# has existed: fetch_posts preloaded :image, which is an attachment rather than
# an association, so every scheduled run raised AssociationNotFoundError and
# spent its three inherited retries raising it again.
class NewsletterEditionBuilderTest < ActiveSupport::TestCase
  setup do
    # Domain unique per run as well as slug: City validates domain for
    # uniqueness, and a fixed one collides with any row a `rails runner` left
    # behind — the test DB is not reset between those and a test run.
    stamp = SecureRandom.hex(3)
    @city = City.create!(name: "Testby", slug: "testby-#{stamp}", domain: "testby-#{stamp}.example",
                        country_code: "NO", locale: "nb", currency: "NOK", time_zone: "Europe/Oslo")
    @author = User.create!(email_address: "letters-#{SecureRandom.hex(4)}@example.com", password: "secret123!")
  end

  test "composes a daily edition for a city that has posts" do
    ActsAsTenant.with_tenant(@city) do
      Post.create!(user: @author, title: "Sol på Fløyen", content: "Fint vær i dag.")
    end

    editions = NewsletterEditionBuilder.compose_daily!(city: @city.slug)

    assert_predicate editions, :any?
    assert(editions.all? { |edition| edition.is_a?(NewsletterEdition) },
           "expected persisted editions, got #{editions.map(&:class).uniq.inspect}")
  end

  # Composing is not enough. Running the fixed builder against production put 12
  # editions in the table and logged "newsletter url skipped: ArgumentError"
  # once per story: url_for has no request to take a host from, so every link
  # and every image came back nil and the letters shipped with nothing to click.
  test "stories carry an absolute link on the city's own domain" do
    ActsAsTenant.with_tenant(@city) do
      Post.create!(user: @author, title: "Klikkbar", content: "Med lenke.")
    end

    edition = NewsletterEditionBuilder.compose_daily!(city: @city.slug).first
    urls = Array(edition.stories).filter_map { |story| story["url"] || story[:url] }

    assert_predicate urls, :any?, "every story link was dropped"
    assert(urls.all? { |url| url.start_with?("https://#{@city.domain}/") },
           "expected links on #{@city.domain}, got #{urls.inspect}")
  end

  # Names the defect directly rather than through the builder, so a rewrite of
  # fetch_posts cannot quietly reintroduce it under a different call shape. The
  # row matters: with an empty table Rails never runs the preload, which is why
  # a test suite that creates no posts could not have caught this.
  test "a post image is preloadable as an attachment, not as an association" do
    ActsAsTenant.with_tenant(@city) do
      Post.create!(user: @author, title: "Bilde", content: "Med vedlegg.")
    end

    assert_nothing_raised { Post.includes(:user).with_attached_image.limit(1).to_a }
    assert_raises(ActiveRecord::AssociationNotFoundError) { Post.includes(:image).limit(1).to_a }
  end
end
