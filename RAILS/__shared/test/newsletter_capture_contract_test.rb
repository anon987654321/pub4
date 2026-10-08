# frozen_string_literal: true

require "minitest/autorun"

class NewsletterCaptureContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CONTROLLER = File.join(ROOT, "shared/frontend/newsletter_capture_controller.js")
  VIEW = File.join(ROOT, "shared/app/views/shared/_newsletter_signup_popup.html.erb")
  IMPORTMAP = File.join(ROOT, "shared/config/importmap_baseline.rb")
  BOOT = File.join(ROOT, "shared/frontend/stimulus_boot.js")
  FOOTER = File.join(ROOT, "shared/app/views/shared/_site_legal_footer.html.erb")
  VISUALS = File.join(ROOT, "shared/app/services/shared/newsletter_visuals.rb")
  COMPOSER = File.join(ROOT, "shared/app/services/shared/newsletter_composer.rb")
  EDITION = File.join(ROOT, "shared/app/views/shared/newsletter/_edition.html.erb")
  MODEL = File.join(File.expand_path("../..", __dir__), "brgen/app/models/newsletter_edition.rb")

  def test_popup_is_shared_and_time_capped
    body = File.read(VIEW)
    controller = File.read(CONTROLLER)

    assert_includes body, %(data-controller="newsletter-capture")
    assert_includes body, %(email_subscription[agreed_to_marketing])
    assert_includes body, %(newsletter_popup.reward)
    assert_includes controller, "7 * 24 * 60 * 60 * 1000"
    assert_includes controller, "showModal()"
  end

  def test_popup_is_wired_once_through_shared_boot
    assert_includes File.read(IMPORTMAP), %(pin "pub4/newsletter_capture")
    assert_includes File.read(BOOT), %(import NewsletterCapture from "pub4/newsletter_capture")
    assert_includes File.read(BOOT), %(application.register("newsletter-capture", NewsletterCapture))
  end

  def test_brgen_home_mounts_existing_subscription_endpoint
    footer = File.read(FOOTER)
    assert_includes footer, %(render "shared/newsletter_signup_popup")
    assert_includes footer, "email_subscriptions_path"
  end

  def test_newsletters_carry_replicate_artwork
    visuals = File.read(VISUALS)
    composer = File.read(COMPOSER)
    edition = File.read(EDITION)
    model = File.read(MODEL)

    assert_includes visuals, "REPLICATE_MODEL"
    assert_includes visuals, "artworks_for"
    assert_includes visuals, "source: :replicate"
    assert_includes composer, ":artworks"
    assert_includes edition, %(render "shared/newsletter/artwork")
    assert_includes model, "artwork_from_json"
  end

  def test_newsletter_provider_is_called_replicate
    visuals = File.read(VISUALS)
    refute_includes visuals, "preprompt_hero"
    refute_includes visuals, "PREPROMPT_MODEL"
    refute_includes visuals, "source: :preprompt"
  end
end
