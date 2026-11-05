# frozen_string_literal: true

require "test_helper"

# Every string exists in both languages, and every static key the app asks
# for is there.
class LocaleFilesTest < ActiveSupport::TestCase
  PLURAL_KEYS = %w[zero one two few many other].freeze

  test "nb and en carry the same keys" do
    nb = locale_keys("nb")
    en = locale_keys("en")

    assert_empty nb - en, "missing in en.yml"
    assert_empty en - nb, "missing in nb.yml"
  end

  test "every static key used in app/ exists" do
    keys = locale_keys("nb")
    used = Rails.root.glob("app/**/*.{rb,erb}").flat_map { |path| path.read.scan(/\bt\(\s*["']([a-z_][\w.]*)["']/) }
    missing = used.flatten.uniq.reject do |key|
      keys.include?(key) || keys.any? { |known| known.start_with?("#{key}.") }
    end

    assert_empty missing
  end

  private

  def locale_keys(locale)
    flatten_keys(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale))
  end

  # A plural hash (one/other) is one key; any other hash nests.
  def flatten_keys(tree, prefix = nil)
    tree.flat_map do |name, value|
      key = [ prefix, name ].compact.join(".")
      nested = value.is_a?(Hash) && (value.keys - PLURAL_KEYS).any?
      nested ? flatten_keys(value, key) : [ key ]
    end
  end
end
