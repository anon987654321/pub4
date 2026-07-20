# frozen_string_literal: true

require "test_helper"

class RadioBergenManifestTest < ActiveSupport::TestCase
  test "loads youtube tracks from manifest" do
    tracks = Brgen::RadioBergenManifest.youtube_tracks

    assert_operator tracks.size, :>=, 10
    dilla = tracks.find { |t| t[:title] == "Microphone Master" }
    assert_equal "9EGHwkDix78", dilla[:id]
    assert_equal "J Dilla", dilla[:artist]
  end

  test "archaeology lines reference pub4 index.html dig" do
    lines = Brgen::RadioBergenManifest.archaeology_lines

    assert_includes lines.join("\n"), "pub4/index.html"
    assert_includes lines.join("\n"), "monolithic index.html"
    assert_includes lines.join("\n"), "radio_bergen_tracks.yml"
  end
end
