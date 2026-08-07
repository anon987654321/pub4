# frozen_string_literal: true

require "test_helper"
require "pub4/deploy_paths"

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
    assert_includes lines.join("\n"), "config/radio_bergen/tracks.yml"
  end

  # The archaeology lines are rendered to the visitor, so a path in one of them
  # is a claim about this repo. They named studio/radio-bergen/ for weeks after
  # 41b20306d deleted it, and nothing failed.
  test "every repo path in the archaeology lines exists" do
    root = Pathname.new(Pub4::DeployPaths.repo_root)
    paths = Brgen::RadioBergenManifest.archaeology_lines.join("\n")
                                      .scan(%r{\b(?:RAILS|STUDIO|MASTER|OPENBSD)/[\w./-]+\.\w+})

    assert_operator paths.size, :>=, 2, "expected the lines to still cite repo paths"
    paths.each { |rel| assert_path_exists root.join(rel).to_s }
  end
end
