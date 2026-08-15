# frozen_string_literal: true

require "minitest/autorun"

# isolate_namespace drops the vertical prefix from the engine's own helpers.
# ENGINES.md step 4: rewrite every v_X_(path|url) → X_\2 inside engines/v/app.
# The marketplace cart already lost send_offers_marketplace_cart_path that way.
# playlist/show kept embed_playlist_playlist_url after the same extraction, so
# the owner section 500'd — the embed feature the page itself advertises.
class EngineRouteHelpersTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENGINES = %w[playlist marketplace dating takeaway tv maps].freeze

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
      views = Dir.glob(File.join(ROOT, "brgen/engines/#{vertical}/app/views/**/*.erb"))
      refute_empty views, "brgen/engines/#{vertical}/app/views is empty or gone"
    end
  end

  private

  def leftovers_in(vertical)
    pattern = /\b#{Regexp.escape(vertical)}_#{Regexp.escape(vertical)}_[a-z0-9_]+(?:_path|_url)\b/
    Dir.glob(File.join(ROOT, "brgen/engines/#{vertical}/app/{views,helpers,controllers}/**/*.{erb,rb}")).flat_map do |path|
      File.readlines(path, encoding: "UTF-8").each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#", "<%#")
        match = line[pattern]
        next unless match

        "#{path.sub("#{ROOT}/", "")}:#{i + 1}  #{match}"
      end
    end
  end
end
