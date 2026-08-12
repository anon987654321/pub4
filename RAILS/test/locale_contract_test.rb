# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "psych"

# What a locale file has to be true of before anything reads it.
#
# i18n_resolution_test asks whether a key a view uses resolves. This asks the two
# questions that come before that, and both were found by throwaway scripts during
# the 2026-08-12 i18n sweep — scripts that caught real bugs and were then thrown
# away, which is why the bugs stayed findable and this file exists.
#
#   Duplicate keys. Psych keeps the last value for a repeated key and says nothing.
#   A second `auth:` block appended to the end of a locale file silently deleted
#   every key in the first one, including enable_2fa, and the only symptom was a
#   translation_missing on a page nobody had loaded that week. YAML.safe_load_file
#   cannot see this after the fact, so this walks the parse tree instead.
#
#   nb/en parity. Rails falls back to :en for a key nb does not carry, so a missing
#   Norwegian translation renders as English on a Norwegian page and raises nothing.
#   That is the exact failure the sweep spent a day on: 76 English strings on the
#   nb UI, several of them keys that existed in en.yml and not in nb.yml. The
#   fallback is what makes this invisible, so the check has to be on the files.
#
# Both pass as of 2026-08-12. That is the point — they are here so the next one
# fails a test instead of shipping.
class LocaleContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Our own locale files, not the ones vendored gems ship. railties alone carries
  # an en.yml under vendor/bundle in every app.
  def locale_files
    @locale_files ||= Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/config/locales/**/*.yml")).sort
  end

  def test_the_glob_finds_the_locale_files
    refute_empty locale_files, "no locale files found — the glob is wrong, not the tree"
    assert_operator locale_files.size, :>=, 10,
                    "expected at least 10 locale files, found #{locale_files.size}"
  end

  def test_no_locale_file_repeats_a_key
    duplicates = locale_files.flat_map { |path| duplicate_keys(path).map { |dup| [path, dup] } }

    assert_empty duplicates, <<~MSG
      #{duplicates.size} duplicate key(s). YAML keeps the last one and discards
      everything under the first, silently:

      #{duplicates.map { |path, (key, line, first)|
          "  #{rel(path)}:#{line}  #{key}  (already defined at line #{first})"
        }.join("\n")}
    MSG
  end

  # One root per file, and it has to be the locale the filename claims. flat_keys
  # in i18n_resolution_test reads `.values.first`, so a file with a second root
  # would have every key under it read by nothing at all.
  def test_each_locale_file_has_one_root_naming_its_own_locale
    wrong = locale_files.filter_map do |path|
      roots = (YAML.safe_load_file(path, aliases: true) || {}).keys
      expected = File.basename(path, ".yml").split(".").last
      next if roots == [expected]

      "#{rel(path)}: roots #{roots.inspect}, filename says #{expected.inspect}"
    end

    assert_empty wrong, "locale files whose root does not match their name:\n  #{wrong.join("\n  ")}"
  end

  # Per app, because amber words four auth strings differently from brgen and
  # that is intent, not duplication — the contract is that each app says the same
  # things in both languages, not that all apps say the same things.
  def test_nb_and_en_declare_the_same_keys
    problems = %w[brgen amber bsdports shared].filter_map do |app|
      en = keys_for(app, "en")
      nb = keys_for(app, "nb")
      next if en.empty? && nb.empty?

      only_en = (en - nb).sort
      only_nb = (nb - en).sort
      next if only_en.empty? && only_nb.empty?

      lines = ["#{app}: en=#{en.size} nb=#{nb.size}"]
      lines << "  missing from nb (renders as English on a Norwegian page): #{only_en.join(', ')}" if only_en.any?
      lines << "  missing from en: #{only_nb.join(', ')}" if only_nb.any?
      lines.join("\n")
    end

    assert_empty problems, "en and nb disagree:\n#{problems.join("\n")}"
  end

  private

  def rel(path) = path.sub("#{ROOT}/", "")

  def keys_for(app, locale)
    pattern = app == "shared" ? "shared/config/locales/*.#{locale}.yml" : "#{app}/config/locales/*#{locale}.yml"
    Dir.glob(File.join(ROOT, pattern)).flat_map { |path| flat_keys(path) }.uniq
  end

  def flat_keys(path, node = nil, prefix = [], out = [])
    node ||= (YAML.safe_load_file(path, aliases: true) || {}).values.first || {}
    node.each do |key, value|
      path_keys = prefix + [key.to_s]
      value.is_a?(Hash) ? flat_keys(path, value, path_keys, out) : out << path_keys.join(".")
    end
    out
  end

  # Psych's document tree, not the loaded Hash: by the time YAML.safe_load_file
  # returns, the duplicate is already gone. Mapping children alternate key, value.
  def duplicate_keys(path, node = nil, prefix = [], out = [])
    node ||= Psych.parse_file(path)
    return out unless node

    if node.is_a?(Psych::Nodes::Mapping)
      seen = {}
      node.children.each_slice(2) do |key_node, value_node|
        name = key_node.respond_to?(:value) ? key_node.value : key_node.to_s
        line = key_node.start_line + 1
        if seen[name]
          out << [(prefix + [name]).join("."), line, seen[name]]
        else
          seen[name] = line
        end
        duplicate_keys(path, value_node, prefix + [name], out)
      end
    elsif node.respond_to?(:children) && node.children
      node.children.each { |child| duplicate_keys(path, child, prefix, out) }
    end

    out
  end
end
