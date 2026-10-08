# frozen_string_literal: true

require "test_helper"

class MasterEmbedHelperTest < ActionView::TestCase
  include Shared::MasterEmbedHelper

  def test_master_web_url_reads_config
    Rails.application.config.x.master_web_url = "https://ai.example.test"
    assert_equal "https://ai.example.test", master_web_url
  end

  def test_master_web_url_adds_autostart_and_embed_query
    Rails.application.config.x.master_web_url = "https://ai.example.test"
    url = master_web_url(autostart: true, embed: true)
    assert_includes url, "autostart=1"
    assert_includes url, "embed=1"
    assert_match(%r{\Ahttps://ai\.example\.test\?}, url)
  end

  # Through the key, not the English literal behind it: `master.embed_heading`
  # is translated ("AI-assistent" in nb), and the bare "AI" this asserted is the
  # helper last resort for an app with no locale entry at all. The apps default
  # to Norwegian, so asserting the literal made the translation a failure.
  def test_master_embed_title_falls_back_to_the_translation
    @master_embed_title = nil
    assert_equal I18n.t("master.embed_heading", default: I18n.t("master.title", default: "AI")),
                 master_embed_title
  end

  def test_master_embed_title_uses_instance_variable
    @master_embed_title = "Brgen"
    assert_equal "Brgen", master_embed_title
  end
end
