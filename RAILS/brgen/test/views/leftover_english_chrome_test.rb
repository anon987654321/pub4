# frozen_string_literal: true

require "test_helper"
require "yaml"

class LeftoverEnglishChromeTest < ActiveSupport::TestCase
  ROOT = File.expand_path("../..", __dir__)

  def read(rel)
    File.read(File.join(ROOT, rel))
  end

  test "tv channel owner action uses the tv.upload_video key" do
    source = read("engines/tv/app/views/tv/channels/show.html.erb")
    assert_includes source, 't("tv.upload_video")'
    refute_includes source, '"Upload video"'
  end

  test "takeaway order show does not humanize status" do
    source = read("engines/takeaway/app/views/takeaway/orders/show.html.erb")
    refute_includes source, "status.humanize"
    assert_includes source, 't("takeaway.statuses.'
  end

  test "playlist set card uses privacy and tracks keys" do
    source = read("engines/playlist/app/views/playlist/sets/_card.html.erb")
    refute_includes source, '"Public"'
    refute_includes source, "tracks ·"
    assert_includes source, 't("playlist.privacy.'
  end

  test "chrome_labels locale files pair en and nb keys" do
    en = YAML.safe_load_file(File.join(ROOT, "config/locales/chrome_labels.en.yml")).fetch("en")
    nb = YAML.safe_load_file(File.join(ROOT, "config/locales/chrome_labels.nb.yml")).fetch("nb")
    assert_equal en.keys.sort, nb.keys.sort
    assert en.dig("takeaway", "statuses", "out_for_delivery")
    assert nb.dig("takeaway", "statuses", "out_for_delivery")
  end
end
