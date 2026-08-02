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
        next if framework?(key) || known.key?(key) || plural?(known, key)

        [app, locale, key, file]
      end
    end
  end

  # What Rails loads for this app: its own config/locales plus the engine's social.<locale>.yml.
  def app_keys(app, locale)
    flat_keys("#{app}/config/locales/#{locale}.yml").merge(flat_keys("shared/config/locales/social.#{locale}.yml"))
  end

  # Views and helpers the app can render: its own, plus the engine's.
  def keys_used_by(app)
    @keys_used_by ||= {}
    @keys_used_by[app] ||= begin
      globs = ["#{app}/app/views/**/*.erb", "#{app}/app/helpers/**/*.rb",
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
      keys << key if key && !body.include?("default:")
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

  def plural?(known, key) = known.key?("#{key}.one") || known.key?("#{key}.other")

  def framework?(key) = FRAMEWORK_PREFIXES.any? { |prefix| key.start_with?(prefix) }
end
