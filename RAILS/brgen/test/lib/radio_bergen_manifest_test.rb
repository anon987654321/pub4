# frozen_string_literal: true

require "test_helper"
require "operator/deploy_paths"

class RadioBergenManifestTest < ActiveSupport::TestCase
  test "loads youtube tracks from manifest" do
    tracks = Brgen::RadioBergenManifest.youtube_tracks

    assert_operator tracks.size, :>=, 10
    dilla = tracks.find { |t| t[:title] == "Microphone Master" }
    assert_equal "9EGHwkDix78", dilla[:id]
    assert_equal "J Dilla", dilla[:artist]
  end

  # pub4/index.html is a path inside the anon987654321/pub2 archive, which is
  # history and cannot be renamed. The rename that reached this line renamed a
  # command — MASTER/bin/pub4 became bin/operator — and the repository is still
  # pub4. A word-boundary rewrite cannot tell a live path from a cited one.
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
    root = Pathname.new(Operator::DeployPaths.repo_root)
    paths = Brgen::RadioBergenManifest.archaeology_lines.join("\n")
                                      .scan(%r{\b(?:RAILS|STUDIO|MASTER|OPENBSD)/[\w./-]+\.\w+})

    assert_operator paths.size, :>=, 2, "expected the lines to still cite repo paths"
    paths.each { |rel| assert_path_exists root.join(rel).to_s }
  end
end
