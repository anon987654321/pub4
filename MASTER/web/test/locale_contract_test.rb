# frozen_string_literal: true

require "test_helper"
require "yaml"
require "psych"

# Same two questions RAILS/test/locale_contract_test.rb asks, for this app.
# That file's glob is RAILS/{brgen,amber,bsdports,shared} — it has never
# seen MASTER/web. application.rb pointed at it anyway, which is how the
# face shipped t("face.mic_state", default: "Microphone") on a page whose
# html lang was still hardcoded "en" after the default locale became :nb.
class LocaleContractTest < ActionDispatch::IntegrationTest
  LOCALES_DIR = File.expand_path("../config/locales", __dir__)

  def locale_files
    @locale_files ||= Dir.glob(File.join(LOCALES_DIR, "*.yml")).sort
  end

  def test_the_glob_finds_both_locales
    names = locale_files.map { |path| File.basename(path) }
    assert_includes names, "en.yml"
    assert_includes names, "nb.yml"
  end

  def test_no_locale_file_repeats_a_key
    duplicates = locale_files.flat_map { |path| duplicate_keys(path).map { |dup| [path, dup] } }

    assert_empty duplicates, <<~MSG
      #{duplicates.size} duplicate key(s). YAML keeps the last one and discards
      everything under the first, silently:

      #{duplicates.map { |path, (key, line, first)|
          "  #{File.basename(path)}:#{line}  #{key}  (already defined at line #{first})"
        }.join("\n")}
    MSG
  end

  def test_nb_and_en_declare_the_same_keys
    en = flat_keys(File.join(LOCALES_DIR, "en.yml"))
    nb = flat_keys(File.join(LOCALES_DIR, "nb.yml"))
    only_en = (en - nb).sort
    only_nb = (nb - en).sort

    problems = []
    problems << "missing from nb (renders as English on a Norwegian page): #{only_en.join(', ')}" if only_en.any?
    problems << "missing from en: #{only_nb.join(', ')}" if only_nb.any?

    assert_empty problems, "en and nb disagree:\n  #{problems.join("\n  ")}"
  end

  private

  def flat_keys(path, node = nil, prefix = [], out = [])
    node ||= (YAML.safe_load_file(path, aliases: true) || {}).values.first || {}
    node.each do |key, value|
      path_keys = prefix + [key.to_s]
      value.is_a?(Hash) ? flat_keys(path, value, path_keys, out) : out << path_keys.join(".")
    end
    out
  end

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
