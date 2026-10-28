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

  test "preserves all 35 selected archive tracks and their original order" do
    tracks = Brgen::RadioBergenManifest.curated_tracks
    expected_files = %w[
      j_dilla-players_second_version.mp3 johann-amiga.mp3 johann-radio_bergen_1.mp3
      johann-rauingar.mp3 haisam_and_johann-pb1.mp3 mike_t_and_johann-alt_kan_skje.mp3
      jan_hakim_and_johann-stailings_a.mp3 jan_hakim_and_johann-stailings_b.mp3
      johann-lofi.mp3 angelo_reira_and_johann-sandviken_hotell_a.mp3
      angelo_reira_and_johann-sandviken_hotell_b.mp3 whyppedcream-hemmelig_3.mp3
      whyppedcream-hemmelig_2.mp3 whyppedcream-hemmelig_1.mp3 whyppedcream-medium.mp3
      whyppedcream-heavy.mp3 whyppedcream-regular.mp3 whyppedcream-light.mp3
      chase_swayze-concrete_street.mp3 chase_swayze-greenery.mp3 chase_swayze-shit_is_real.mp3
      chase_swayze-scott_free.mp3 chase_swayze-living_daylights.mp3 chase_swayze-chilly.mp3
      chase_swayze-revenge.mp3 chase_swayze-ants.mp3 chase_swayze-underated.mp3
      chase_swayze-jimmy_johnson.mp3 chase_swayze-eleven.mp3 chase_swayze-unobtanium.mp3
      chase_swayze-sardines.mp3 chase_swayze-cinnamonsistagirl.mp3 chase_swayze-hannah.mp3
      chase_swayze-ijustwannafucku.mp3 chase_swayze-strange.mp3
    ]

    assert_equal 35, tracks.size
    assert_equal (1..35).to_a, tracks.map { |row| row["ordinal"] }
    assert_equal expected_files, tracks.map { |row| row["source_file"] }
    assert_equal "J Dilla", tracks.first["artist"]
    assert_equal "Players (Second Version)", tracks.first["title"]
    assert_equal "Strange", tracks.last["title"]
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
    root = Pathname.new(Shared::Contracts.root)
    paths = Brgen::RadioBergenManifest.archaeology_lines.join("\n")
                                      .scan(%r{\b(?:RAILS|STUDIO|MASTER|OPENBSD)/[\w./-]+\.\w+})

    assert_operator paths.size, :>=, 1, "expected the lines to still cite repo paths"
    paths.each { |rel| assert_path_exists root.join(rel).to_s }
  end
end
