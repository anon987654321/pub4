# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# Every t("literal") without a default must resolve in the locales the app actually loads.
#
# bsdports rendered shared/_live_search_form, whose three status keys only brgen and amber
# carried, and shipped <span class="translation_missing"> inside the data attributes its
# live region announces. Nothing counted that: chrome_i18n_lint measures hardcoded English,
# not keys that fail to resolve, and page_simulation never walks shared/app/views.
#
# Deliberately silent about where a key lives. amber words four auth strings differently
# from brgen and bsdports, so per-app copies are intent, not duplication.
class I18nResolutionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze
  LOCALES = %w[en nb].freeze
  # rails-i18n and ActiveModel supply these; they are not ours to carry.
  FRAMEWORK_PREFIXES = %w[errors. activerecord. activemodel. time. date. datetime. number. helpers. support.].freeze

  def test_every_defaultless_key_resolves_in_every_app
    unresolved = APPS.flat_map { |app| unresolved_keys(app) }

    assert_empty unresolved, "#{unresolved.size} key(s) render as translation_missing:\n" +
                             unresolved.map { |app, locale, key, file| "  #{app} [#{locale}] #{key} <- #{file}" }.join("\n")
  end

  private

  def unresolved_keys(app)
    LOCALES.flat_map do |locale|
      known = app_keys(app, locale)
      keys_used_by(app).filter_map do |key, file|
        next if framework?(key) || known.key?(key) || subtree?(known, key)

        [app, locale, key, file]
      end
    end
  end

  # What Rails loads for this app: everything in its config/locales for this
  # locale, plus the engine's social.<locale>.yml. Globbed rather than named,
  # because Rails loads the whole directory and amber splits its into three
  # files — en.yml, copy.en.yml and validations.en.yml — of which this used to
  # read one.
  #
  # The mountable engines are here for the same reason they are in keys_used_by,
  # and it is the same blind spot in the other direction: this side globbed only
  # the host, so the first engine to carry its own config/locales — every one of
  # them does now — reported its keys as unresolved. Rails::Engine appends
  # config/locales/*.yml to I18n.load_path with no wiring, so a key defined
  # there resolves in the mounting app exactly like a host key.
  def app_keys(app, locale)
    paths = Dir.glob(File.join(ROOT, "#{app}/config/locales/*#{locale}.yml")) +
            Dir.glob(File.join(ROOT, "#{app}/engines/*/config/locales/*#{locale}.yml")) +
            Dir.glob(File.join(ROOT, "shared/config/locales/*.#{locale}.yml"))
    paths.each_with_object({}) { |path, out| out.merge!(flat_keys(path.sub("#{ROOT}/", ""))) }
  end

  # Views and helpers the app can render: its own, the engine's, and — the part
  # this missed — the mountable engines brgen's verticals live in. 102 view and
  # helper files under brgen/engines/*/app were outside the glob, which is the
  # same blind spot that cost four other scanners 57 views when the verticals
  # moved and read as an improving finding count rather than as blindness.
  def keys_used_by(app)
    @keys_used_by ||= {}
    @keys_used_by[app] ||= begin
      globs = ["#{app}/app/views/**/*.erb", "#{app}/app/helpers/**/*.rb",
               "#{app}/engines/*/app/views/**/*.erb", "#{app}/engines/*/app/helpers/**/*.rb",
               "shared/app/views/**/*.erb", "shared/app/helpers/**/*.rb"]
      globs.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }.each_with_object({}) do |path, found|
        defaultless_keys(File.read(path)).each { |key| found[key] ||= path.sub("#{ROOT}/", "") }
      end
    end
  end

  # Balanced-paren scan: t("a.b", default: t("c.d")) must count neither key as unresolved.
  def defaultless_keys(source)
    keys = []
    offset = 0
    while (match = source.match(/\bt\(/, offset))
      offset = match.end(0)
      body = call_body(source, match.end(0) - 1) or next
      key = body[/\A\s*["']([a-z0-9_][a-zA-Z0-9_.]*)["']/, 1]
      next unless key

      # default: "English" still requires the primary key. default: t("other")
      # is a fallback key — do not fail the suite on the inner name.
      prefix = source[[match.begin(0) - 16, 0].max...match.begin(0)]
      next if prefix.match?(/default:\s*\z/)

      keys << key
    end
    keys
  end

  def call_body(source, open)
    depth = 0
    position = open
    while position < source.length
      depth += 1 if source[position] == "("
      if source[position] == ")"
        depth -= 1
        return source[(open + 1)...position] if depth.zero?
      end
      position += 1
    end
    nil
  end

  def flat_keys(relative, node = nil, prefix = [], out = {})
    node ||= (YAML.safe_load_file(File.join(ROOT, relative), aliases: true) || {}).values.first || {}
    node.each do |key, value|
      path = prefix + [key.to_s]
      value.is_a?(Hash) ? flat_keys(relative, value, path, out) : out[path.join(".")] = true
    end
    out
  end

  # A key naming a SUBTREE resolves too, to the Hash under it.
  #
  # This was `known.key?("#{key}.one") || known.key?("#{key}.other")`, which
  # covers pluralisation and nothing else, so it reported
  #
  #   brgen [en] affiliate.cta <- shared/_affiliate_feed_unit.html.erb
  #   brgen [nb] affiliate.cta <- shared/_affiliate_feed_unit.html.erb
  #
  # as missing translations. They are not missing: affiliate.cta.buy, .happy and
  # .good are present in both locales, and the partial deliberately fetches the
  # branch — `t("affiliate.cta").values[...]` rotates through the calls to
  # action. flat_keys records leaves only, so the branch itself never appears in
  # `known` and any caller that wants a Hash reads as broken.
  #
  # Pluralisation is one instance of this rather than the rule, so the check is
  # now "does anything live under this key", which covers both.
  def subtree?(known, key)
    prefix = "#{key}."
    known.any? { |known_key, _| known_key.start_with?(prefix) }
  end

  def framework?(key) = FRAMEWORK_PREFIXES.any? { |prefix| key.start_with?(prefix) }
end
