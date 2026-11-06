# frozen_string_literal: true

require "minitest/autorun"
require_relative "engine_roots"

# isolate_namespace drops the vertical prefix from the engine's own helpers.
# Step 4 of the recipe in brgen/README.md: rewrite every v_X_(path|url) → X_\2 inside engines/v/app.
# The marketplace cart already lost send_offers_marketplace_cart_path that way.
# playlist/show kept embed_playlist_playlist_url after the same extraction, so
# the owner section 500'd — the embed feature the page itself advertises.
class EngineRouteHelpersTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENGINES = EngineRoots::PATHS.keys.freeze

  def test_isolated_engine_views_do_not_call_host_namespaced_helpers
    leftovers = ENGINES.flat_map { |vertical| leftovers_in(vertical) }

    assert_empty leftovers, <<~MSG
      #{leftovers.size} host-namespaced helper(s) inside an isolated engine.
      Under isolate_namespace these raise at render. Rewrite to the unprefixed
      name (embed_playlist_url, not embed_playlist_playlist_url):

      #{leftovers.map { |hit| "  #{hit}" }.join("\n")}
    MSG
  end

  def test_the_glob_still_sees_the_engines
    ENGINES.each do |vertical|
      views = Dir.glob(File.join(ROOT, "#{EngineRoots::PATHS.fetch(vertical)}/app/views/**/*.erb"))
      refute_empty views, "#{EngineRoots::PATHS.fetch(vertical)}/app/views is empty or gone"
    end
  end

  def test_duplicate_engine_helper_detector_catches_a_real_regression
    pattern = duplicate_engine_helper_pattern("playlist")

    assert_match pattern, "embed_playlist_playlist_url"
    refute_match pattern, "embed_playlist_url"
  end

  private

  def leftovers_in(vertical)
    helper_pattern = duplicate_engine_helper_pattern(vertical)
    glob = File.join(ROOT, EngineRoots::PATHS.fetch(vertical), "app/{views,helpers,controllers}/**/*.{erb,rb}")
    Dir.glob(glob).flat_map do |path|
      File.readlines(path, encoding: "UTF-8").each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#", "<%#")
        match = line[helper_pattern]
        next unless match

        "#{path.sub("#{ROOT}/", "")}:#{i + 1}  #{match}"
      end
    end
  end

  def duplicate_engine_helper_pattern(vertical)
    /(?<![a-z0-9])#{Regexp.escape(vertical)}_#{Regexp.escape(vertical)}(?=_|$)/
  end
end
