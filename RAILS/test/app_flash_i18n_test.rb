# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# OPENBSD/data/debt.yml, rails_flash_strings_untranslated: 169 hardcoded English
# flash strings across the family, every one of them a toast in English over a
# Norwegian page, because all three apps set default_locale = :nb.
#
# This test replaced a first version that could not have caught the bug it was
# written for. That version compared the KEY NAMES used in code against the key
# names in the YAML, and the shared engine's block had been appended at the top
# level while every call site said t("shared.flash.…"): the names matched, the
# paths did not, and all 30 messages resolved to a translation-missing span.
#
# So this walks the actual dotted path into the loaded YAML. A test over key names
# is a test over spelling; a test over paths is a test over resolution.
#
# It also caught the second half of the same mistake: amber's own test asserted
# `assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]`, which passes
# when the key is missing, because both sides are then the same missing-translation
# string. Comparing two lookups of a broken key is a tautology.
class AppFlashI18nTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # tree => [nb file, en file]. The shared engine ships its locales to all three
  # apps through the shared.i18n initializer.
  LOCALES = {
    "shared" => ["shared/config/locales/social.nb.yml", "shared/config/locales/social.en.yml"],
    "amber" => ["amber/config/locales/nb.yml", "amber/config/locales/en.yml"],
    "bsdports" => ["bsdports/config/locales/nb.yml", "bsdports/config/locales/en.yml"],
    "brgen" => ["brgen/config/locales/nb.yml", "brgen/config/locales/en.yml"],
  }.freeze

  # Where each tree's controllers live. brgen's verticals are engines, and a
  # single-level glob goes blind to all five of them.
  CONTROLLERS = {
    "shared" => ["shared/app/controllers/**/*.rb"],
    "amber" => ["amber/app/controllers/**/*.rb"],
    "bsdports" => ["bsdports/app/controllers/**/*.rb"],
    "brgen" => ["brgen/app/controllers/**/*.rb", "brgen/engines/*/app/controllers/**/*.rb"],
  }.freeze

  def load_locale(relative, locale)
    YAML.safe_load_file(File.join(ROOT, relative)).fetch(locale)
  end

  # Every "…flash.…" key a tree's controllers actually ask for, comments removed.
  #
  # Any string literal, not only one directly after `t(`: reactions_controller picks
  # its key with a ternary INSIDE the call — t(@active ? "…added" : "…removed") — and
  # a regex anchored on `t("` reported both of those keys as declared-but-unused.
  def keys_used_by(tree)
    CONTROLLERS.fetch(tree).flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }.flat_map do |file|
      File.readlines(file, encoding: "UTF-8")
          .reject { |line| line.strip.start_with?("#") }
          .join
          .scan(/"((?:[\w.]*\.)?flash\.[\w.]+)"/).flatten
    end.uniq.sort
  end

  # Keys built by interpolation — t("flash.marketplace.payment_statuses.#{status}")
  # in checkouts_controller. The literal scan above cannot see the leaves, so
  # the namespace up to the interpolation counts as used and everything under
  # it is covered. Without this the five payment_statuses read as inert copy
  # while a live redirect renders one of them on every checkout.
  def dynamic_prefixes_used_by(tree)
    CONTROLLERS.fetch(tree).flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }.flat_map do |file|
      File.readlines(file, encoding: "UTF-8")
          .reject { |line| line.strip.start_with?("#") }
          .join
          .scan(/"((?:[\w.]*\.)?flash\.[\w.]*?)\#\{/).flatten
    end.uniq
  end

  def resolve(locale_hash, dotted)
    locale_hash.dig(*dotted.split("."))
  end

  # The engine's own pair, loaded once: a shared.* key belongs to the engine
  # whichever app asks for it, because every app loads these two files through the
  # shared.i18n initializer.
  def shared_locales
    @shared_locales ||= [load_locale(LOCALES.fetch("shared").first, "nb"),
                         load_locale(LOCALES.fetch("shared").last, "en")]
  end

  def flash_block(locale_hash)
    locale_hash.dig("shared", "flash") || locale_hash["flash"] || {}
  end

  # I18n pluralisation: a controller asks for flash.x.y and I18n picks the
  # branch from the count, so the branches are part of one key, not keys.
  PLURAL_BRANCHES = %w[zero one two few many other].freeze

  # Dotted paths to the leaves. flash_block.keys only ever returned the top
  # level, so once the verticals gained their own namespaces (flash.dating.*,
  # flash.marketplace.* …) the parents read as keys no controller asks for --
  # true, and not the question -- while every leaf underneath them went
  # unchecked, which is the half that catches inert copy.
  def leaf_keys(node, prefix = [])
    return [prefix.join(".")] unless node.is_a?(Hash)
    return [prefix.join(".")] if node.keys.all? { |k| PLURAL_BRANCHES.include?(k.to_s) }

    node.flat_map { |key, value| leaf_keys(value, prefix + [key.to_s]) }
  end

  def test_every_key_a_controller_asks_for_resolves_in_both_locales
    LOCALES.each do |tree, (nb_file, en_file)|
      nb = load_locale(nb_file, "nb")
      en = load_locale(en_file, "en")

      keys_used_by(tree).each do |key|
        owner_nb, owner_en = key.start_with?("shared.") ? shared_locales : [nb, en]
        owner_files = key.start_with?("shared.") ? LOCALES.fetch("shared") : [nb_file, en_file]

        refute_nil resolve(owner_nb, key), "#{tree}: t(\"#{key}\") resolves to nothing in #{owner_files.first}"
        refute_nil resolve(owner_en, key), "#{tree}: t(\"#{key}\") resolves to nothing in #{owner_files.last}"
      end
    end
  end

  # Shared keys are asked for from every app, so they must resolve for a reader
  # that only loaded the engine's file — which is how Rails merges them.
  def test_the_engine_namespaces_its_own_keys
    nb = load_locale(LOCALES.fetch("shared").first, "nb")

    refute_nil nb.dig("shared", "flash"),
               "the engine's flash keys must live under shared: so the call sites resolve " \
               "and so an app can keep its own flash: block without colliding"
    assert_nil nb["flash"], "a top-level flash: block in the engine would merge into every app's"
  end

  def test_both_locales_of_each_tree_carry_the_same_flash_keys
    LOCALES.each do |tree, (nb_file, en_file)|
      nb = flash_block(load_locale(nb_file, "nb"))
      en = flash_block(load_locale(en_file, "en"))
      next if nb.empty? && en.empty?

      assert_equal nb.keys.sort, en.keys.sort,
                   "#{tree}: nb and en disagree about which flash keys exist"
    end
  end

  # An %{interpolation} in one locale and not the other raises
  # I18n::MissingInterpolationArgument for that locale only — a 500 on an error
  # path, which is where nobody looks.
  def test_interpolations_match_between_locales
    placeholders = ->(text) { text.to_s.scan(/%\{(\w+)\}/).flatten.sort }

    LOCALES.each do |tree, (nb_file, en_file)|
      nb = flash_block(load_locale(nb_file, "nb"))
      en = flash_block(load_locale(en_file, "en"))

      nb.each_key do |key|
        assert_equal placeholders.call(nb[key]), placeholders.call(en[key]),
                     "#{tree}.#{key}: nb and en interpolate different names"
      end
    end
  end

  # A declared key no controller asks for is inert config that reads as live copy.
  def test_no_declared_flash_key_is_unused
    used = LOCALES.keys.flat_map { |tree| keys_used_by(tree) }.uniq
    dynamic = LOCALES.keys.flat_map { |tree| dynamic_prefixes_used_by(tree) }.uniq

    LOCALES.each do |tree, (nb_file, _)|
      block = flash_block(load_locale(nb_file, "nb"))
      next if block.empty?

      prefix = tree == "shared" ? "shared.flash." : "flash."
      unused = (leaf_keys(block).map { |key| "#{prefix}#{key}" } - used)
               .reject { |key| dynamic.any? { |stem| key.start_with?(stem) } }

      assert_empty unused, "#{tree}: declared and asked for by no controller"
    end
  end

  # Each interpolated key must be called with an argument list.
  def test_interpolated_keys_are_called_with_arguments
    LOCALES.each do |tree, (nb_file, _)|
      block = flash_block(load_locale(nb_file, "nb"))
      bodies = CONTROLLERS.fetch(tree).flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
                          .map { |file| File.read(file) }.join
      prefix = tree == "shared" ? "shared.flash." : "flash."

      block.select { |_, text| text.to_s.include?("%{") }.each_key do |key|
        call = bodies[/t\(\s*"#{Regexp.escape(prefix)}#{key}"[^)]*\)/]
        next if call.nil? # covered by test_no_declared_flash_key_is_unused

        assert_match(/,/, call, "#{tree}: t(\"#{prefix}#{key}\") is called with no interpolation argument")
      end
    end
  end

  # The engine ships its locale files to every app; if the initializer stops
  # loading them every flash in the family becomes a missing span at once.
  #
  # Asserted as "every file it carries is loaded", not as the literal string
  # `config/locales/social.`, which is what this used to look for. The
  # initializer named that one file and affiliate.en.yml sat beside it unloaded;
  # widening it to a glob was the fix, and left this assertion looking for a
  # string the corrected code no longer contains. A test that fails when the bug
  # it describes is fixed is a test measuring the wrong thing.
  def test_the_engine_still_loads_every_locale_file_it_carries
    engine = File.read(File.join(ROOT, "shared/lib/shared/engine.rb"))
    loaded = engine[/Dir\[root\.join\("(config\/locales\/[^"]+)"\)/, 1]

    assert loaded, "the i18n initializer no longer globs config/locales"
    assert_includes engine, "i18n.load_path"

    shipped = Dir.glob(File.join(ROOT, "shared/config/locales/*.yml")).map { |path| File.basename(path) }
    pattern = File.join(ROOT, "shared", loaded)
    covered = Dir.glob(pattern).map { |path| File.basename(path) }

    assert_equal shipped.sort, covered.sort,
                 "the engine carries locale files the initializer does not load: #{(shipped - covered).join(', ')}"
  end
end
