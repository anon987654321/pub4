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

  def test_master_embed_title_falls_back
    @master_embed_title = nil
    assert_equal "AI", master_embed_title
  end

  def test_master_embed_title_uses_instance_variable
    @master_embed_title = "Brgen"
    assert_equal "Brgen", master_embed_title
  end
end
