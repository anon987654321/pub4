# frozen_string_literal: true

# brgen is one app serving a different city per domain: brgen.no is Bergen,
# oshlo.no is Oslo, lndon.uk is London. DomainRegistry resolves the host and sets
# Current.city before any view renders, and it works — oshlo.no returns 200 with
# rel="canonical" pointing at itself.
#
# It still rendered "Bergen — Brgen", because pages.home_title was the literal
# string "Bergen" in both locales. Every city in the world got Bergen's name on
# Bergen's title, on a platform whose entire premise is that it does not.
#
# The city name belongs in an interpolation, never in a translated value.

require "minitest/autorun"
require "yaml"

class CityCopyContractTest < Minitest::Test
  ROOT = File.expand_path("../brgen", __dir__)
  LOCALES = %w[en nb].freeze

  # Cities brgen serves. A locale value naming one of these has baked a single
  # city into copy every other city also renders.
  CITIES = %w[Bergen Oslo Trondheim Stavanger London Amsterdam Birmingham
              Cardiff Edinburgh Glasgow Liverpool Manchester Copenhagen
              Stockholm Helsinki Reykjavik Gothenburg Malmo].freeze

  # Prose that legitimately names Bergen: legal text naming a jurisdiction, and
  # bot personas written for the one city that has them.
  ALLOWED_KEYS = %w[terms privacy legal jurisdiction about].freeze

  def flatten(node, path = [], out = {})
    case node
    when Hash then node.each { |k, v| flatten(v, path + [k.to_s], out) }
    when Array then node.each_with_index { |v, i| flatten(v, path + [i.to_s], out) }
    else out[path.join(".")] = node.to_s
    end
    out
  end

  # The file is rooted at the locale code, so every path arrives as
  # "en.pages.home_title". Callers name keys the way the views do.
  def values_for(locale)
    file = File.join(ROOT, "config/locales/#{locale}.yml")
    flatten(YAML.safe_load_file(file)).transform_keys { |key| key.sub(/\A#{locale}\./, "") }
  end

  def offenders_for(locale)
    values_for(locale).reject do |key, _|
      ALLOWED_KEYS.any? { |allowed| key.include?(allowed) }
    end.select do |_, value|
      CITIES.any? { |city| value.match?(/(?<![\w])#{Regexp.escape(city)}(?![\w])/) }
    end
  end

  def test_no_locale_value_names_a_city
    offenders = LOCALES.flat_map do |locale|
      offenders_for(locale).map { |key, value| "#{locale}.yml #{key}: #{value.inspect}" }
    end

    assert_empty offenders,
                 "locale values naming a city. brgen serves a different city per domain, so a city " \
                 "name in copy renders on every other city too — interpolate %{city} and pass " \
                 "city: city_name:\n  #{offenders.join("\n  ")}"
  end

  def test_the_city_bearing_keys_interpolate
    LOCALES.each do |locale|
      values = values_for(locale)
      %w[pages.home_title pages.default_description posts.community_platform empty.post_to_city marketplace.home_title marketplace.deals.show_title hashtag.also_in_city communities.also_in_city marketplace.stores.also_in_city].each do |key|
        assert values.key?(key), "#{locale}.yml lost #{key}"
        assert_includes values[key], "%{city}", "#{locale}.yml #{key} no longer interpolates the city"
      end
    end
  end

  def test_layout_does_not_hardcode_bergen_or_a_brgen_title_suffix
    layout = File.read(File.join(ROOT, "app/views/layouts/application.html.erb"))
    refute_match(/— Brgen/, layout,
                 "the title suffix was the city leak: every host rendered 'Page — Brgen'")
    refute_match(/organization_json_ld\(site_name: "Brgen"/, layout)
    refute_includes layout, "city communities across Scandinavia"
    assert_includes layout, "city_name"
    assert_includes layout, "pages.default_description"
    assert_includes layout, "website_json_ld"
  end

  # The layout assertion above pins one file by path, and the leak class is
  # "a hardcoded brand string on any city-facing surface". The manifest is proof
  # that scoping the check to one file lets the next one drift: it named the app
  # "Brgen" and carried the Scandinavia sentence long after the layout stopped.
  BRAND_LEAKS = [
    [/city communities across scandinavia/i, "the pan-European blurb: every city got the same description"],
    [/"Brgen (Playlist|Dating|TV|Marketplace|Takeaway|Maps|Messenger)"/, "a vertical app name fixed to Brgen"],
  ].freeze

  def test_city_facing_surfaces_do_not_hardcode_the_brand
    surfaces = Dir.glob(File.join(ROOT, "app/views/{layouts,pwa}/**/*.erb"))
    refute_empty surfaces, "found no layout/manifest surfaces — the glob has gone stale"
    surfaces.each do |path|
      body = File.read(path)
      BRAND_LEAKS.each do |pattern, why|
        refute_match(pattern, body, "#{path.sub(ROOT, "")}: #{why}")
      end
    end
  end

  def test_the_manifest_resolves_its_name_from_the_city
    manifest = File.read(File.join(ROOT, "app/views/pwa/manifest.json.erb"))
    assert_includes manifest, "city_name",
                    "the manifest is served to the same page as the head; both must resolve the city the same way"
  end

  def test_city_name_helper_exists
    helper = File.read(File.join(ROOT, "app/helpers/application_helper.rb"))
    assert_includes helper, "def city_name",
                    "ApplicationHelper#city_name is what views pass to the interpolations"
    assert_includes helper, "Current.city"
  end

  # The checker reads YAML; if the file moves or empties, every assertion above
  # passes having examined nothing.
  def test_the_checker_measures_something
    LOCALES.each do |locale|
      values = values_for(locale)
      assert_operator values.size, :>, 200, "#{locale}.yml yielded only #{values.size} keys"
    end
  end
end
