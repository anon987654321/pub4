# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "psych"

# What a locale file has to be true of before anything reads it.
#
# i18n_resolution_test asks whether a key a view uses resolves. This asks the
# questions that come before that, found by throwaway scripts during the
# 2026-08-12 i18n sweep — scripts that caught real bugs and were then thrown
# away, which is why the bugs stayed findable and this file exists.
#
#   Duplicate keys. Psych keeps the last value for a repeated key and says nothing.
#   A second `auth:` block appended to the end of a locale file silently deleted
#   every key in the first one, including enable_2fa, and the only symptom was a
#   translation_missing on a page nobody had loaded that week. YAML.safe_load_file
#   cannot see this after the fact, so this walks the parse tree instead.
#
#   One home per key. The same silence one directory up: Rails merges every file
#   in a locale directory in sorted order, so a key defined in two of them renders
#   from whichever file sorts last and the other definition is read by nobody.
#   amber kept eleven English strings in copy.en.yml that en.yml overrode —
#   "Analysis unavailable" against "No analysis for this garment yet." — and the
#   symptom was prose a person had written and no reader could reach.
#
#   nb/en parity. Rails falls back to :en for a key nb does not carry, so a missing
#   Norwegian translation renders as English on a Norwegian page and raises nothing.
#   That is the exact failure the sweep spent a day on: 76 English strings on the
#   nb UI, several of them keys that existed in en.yml and not in nb.yml. The
#   fallback is what makes this invisible, so the check has to be on the files.
#
#   A reader per key. A key no source can reach is copy nobody sees, and it is
#   the copy the next author edits when the page says something else. The search
#   is conservative on purpose: a lazy t(".x"), an interpolated key, a scope: and
#   a fetched subtree each spare what they could reach, so a hit is a key no
#   spelling in the tree can produce.
#
# They all pass. That is the point — they are here so the next one fails a test
# instead of shipping.
class LocaleContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Our own locale files, not the ones vendored gems ship. railties alone carries
  # an en.yml under vendor/bundle in every app. brgen's verticals are engines,
  # and each carries its own config/locales that Rails loads beside the host's.
  def locale_files
    @locale_files ||= Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared,brgen/engines/*}/config/locales/**/*.yml")).sort
  end

  # Each unit that owns a locale directory, so a vertical's strings are held to
  # the same parity as the app mounting it.
  def locale_units
    @locale_units ||= %w[brgen amber bsdports shared] +
                      Dir.glob(File.join(ROOT, "brgen/engines/*/config/locales")).sort.map { |dir| rel(dir).delete_suffix("/config/locales") }
  end

  def test_the_glob_finds_the_locale_files
    refute_empty locale_files, "no locale files found — the glob is wrong, not the tree"
    assert_operator locale_files.size, :>=, 10,
                    "expected at least 10 locale files, found #{locale_files.size}"
    assert_operator locale_units.count { |unit| unit.start_with?("brgen/engines/") }, :>=, 6,
                    "fewer than six engine locale directories — the glob is wrong, not the tree"
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

  # Within one directory, because across directories the shadowing is the override
  # mechanism rather than a bug: an app's config/locales loads after the engines it
  # mounts, which is how amber words six of its shared strings differently. A key
  # with two homes in one directory has no such reason — one of them renders and
  # the other is dead copy.
  def test_no_key_has_two_homes_in_one_locale_directory
    collisions = locale_groups.flat_map do |(app, locale), paths|
      next [] if paths.size < 2

      homes = paths.each_with_object({}) do |path, out|
        flat_values(path).each { |key, value| (out[key] ||= []) << [File.basename(path), value] }
      end

      homes.select { |_, defs| defs.size > 1 }.sort.map do |key, defs|
        winner, dead = defs.last, defs[0..-2]
        "#{app} [#{locale}] #{key}: #{winner[0]} #{winner[1].inspect} renders, " \
          "#{dead.map { |file, value| "#{file} #{value.inspect}" }.join(' and ')} #{dead.one? ? 'is' : 'are'} dead"
      end
    end

    assert_empty collisions, <<~MSG
      #{collisions.size} key(s) with two homes. Rails merges a locale directory in
      sorted order, so the file that sorts last wins and every other definition is
      read by nobody. Delete the dead copy, or move the survivor to it:

      #{collisions.map { |line| "  #{line}" }.join("\n")}
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
    problems = locale_units.filter_map do |app|
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

  # A key both locales declare must interpolate the same names. `%{count}` in nb
  # and absent from en renders fine in en and raises MissingInterpolationArgument
  # nowhere, because the caller passes count; the reverse renders the literal
  # `%{count}` on the page. app_flash_i18n_test holds this for flash keys only.
  def test_nb_and_en_interpolate_the_same_names
    problems = locale_units.flat_map do |app|
      interpolation_mismatches(values_for(app, "en"), values_for(app, "nb")).map { |line| "#{app} #{line}" }
    end

    assert_empty problems, "nb and en interpolate different names:\n  #{problems.join("\n  ")}"
  end

  def test_the_interpolation_check_flags_a_missing_or_renamed_name_and_spares_order
    en = { "cart.count" => "%{count} items in %{city}", "cart.sum" => "%{count} total", "cart.title" => "%{city}: %{count}" }
    nb = { "cart.count" => "%{count} varer", "cart.sum" => "%{antall} totalt", "cart.title" => "%{count} i %{city}" }

    assert_equal [ %(cart.count: en ["city", "count"], nb ["count"]), %(cart.sum: en ["count"], nb ["antall"]) ],
                 interpolation_mismatches(en, nb)
  end

  # Per unit, against the source that can load its files: an app's copy of a key
  # that only another app renders is still dead in the app that carries it.
  def test_every_key_has_a_reader
    unread = locale_units.flat_map do |unit|
      unread_keys(keys_for(unit, "en"), sources_for(unit)).map { |key| "#{unit} #{key}" }
    end

    assert_empty unread, "#{unread.size} key(s) no source reads — delete them from en and nb:\n  #{unread.join("\n  ")}"
  end

  def test_the_reader_search_flags_an_unread_key_and_spares_every_way_a_key_is_built
    keys = %w[
      nav.home nav.dead errors.messages.blank save
      listings.index.heading orders.show.flash.done kinds.bike
      status.open cta.buy mark_open review.issue.spam app.title nav.from_config
    ]
    sources = {
      "app/views/layouts/_nav.html.erb" => %(<%= t("nav.home") %> <%= t(:save) %>),
      "app/views/listings/index.html.erb" => %(<%= t(".heading") %>),
      "app/controllers/orders_controller.rb" => %(redirect_to root_path, notice: t(".flash.done")),
      "app/controllers/map_controller.rb" => %(I18n.t(kind, scope: "kinds")),
      "app/models/order.rb" => %(I18n.t("status.\#{status}")),
      "app/views/shared/_cta.html.erb" => %(<%= t("cta").values.sample %> <%= t("review.issue").keys %>),
      "app/helpers/mark_helper.rb" => %(t(:"mark_\#{state}")),
      "app/services/banner.rb" => %(SCOPE = "app"\ndef t(key) = I18n.t(key, scope: SCOPE)),
      "config/menu.yml" => %(items:\n  - label: nav.from_config\n),
    }

    assert_equal %w[nav.dead], unread_keys(keys, sources)
  end

  private

  def rel(path) = path.sub("#{ROOT}/", "")

  # Keys no source in `sources` (relative path => text) can reach.
  def unread_keys(keys, sources)
    literal, prefixes, shapes = reader_evidence(sources)
    keys.reject do |key|
      segments = key.split(".")
      FRAMEWORK_ROOTS.include?(segments.first) || literal.include?(key) ||
        (1...segments.size).any? { |depth| literal.include?(segments.first(depth).join(".")) } ||
        prefixes.any? { |prefix| key.start_with?(prefix) } || shapes.any? { |shape| key.match?(shape) }
    end.sort
  end

  # rails-i18n, ActiveModel and the form builder read these by convention.
  FRAMEWORK_ROOTS = %w[errors activerecord activemodel time date datetime number helpers support i18n].freeze
  KEY_LITERAL = /["'`:]([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)(?![\w.])/
  # A config file names a key as a bare YAML value.
  YAML_KEY_VALUE = /:[ \t]+([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)[ \t]*$/
  BARE_KEY_CALL = /\bt\(\s*:?["']?([a-z][a-z0-9_]*)\b(?!\.)/
  # A dotted head anywhere, or any head as the first argument of t(): "a#{x}"
  # outside a call is a string, not a key.
  INTERPOLATED_KEY = /["'`]([a-z][a-z0-9_]*\.[\w.]*)#\{[^}]*\}([\w.]*)|\bt\(\s*:?["']([a-z][a-z0-9_]*)#\{[^}]*\}([\w.]*)/
  SCOPE_STRING = /(?:scope:|SCOPE\s*=)\s*:?["']?([a-z][a-z0-9_.]*)/

  # Three kinds of evidence: exact keys, prefixes under which any key may be
  # built, and shapes an interpolated key can take.
  def reader_evidence(sources)
    literal = Set.new
    prefixes = []
    shapes = []
    sources.each do |path, text|
      text.scan(KEY_LITERAL) { |(key)| literal << key }
      text.scan(YAML_KEY_VALUE) { |(key)| literal << key } if path.end_with?(".yml")
      text.scan(BARE_KEY_CALL) { |(key)| literal << key }
      text.scan(INTERPOLATED_KEY) do |dotted, dotted_tail, called, called_tail|
        shapes << /\A#{Regexp.escape(dotted || called)}[\w.]+#{Regexp.escape(dotted_tail || called_tail)}\z/
      end
      text.scan(SCOPE_STRING) { |(scope)| prefixes << "#{scope}." }
      lazy = lazy_base(path)
      next unless lazy && text.match?(/\bt\(\s*["']\./)

      if path.include?("/views/")
        text.scan(/\bt\(\s*["']\.([a-z0-9_.]+)["']/) { |(tail)| literal << "#{lazy}.#{tail}" }
      else
        prefixes << "#{lazy}."
      end
    end
    [literal, prefixes, shapes]
  end

  # What Rails prefixes a lazy t(".x") with. A view's is its own path, partial
  # underscore dropped; a controller or mailer adds the action, which a text
  # read cannot know, so everything under the controller is spared.
  def lazy_base(path)
    if (view = path[%r{app/views/(.+)\z}, 1])
      view.sub(/\..*\z/, "").split("/").map { |segment| segment.delete_prefix("_") }.join(".")
    elsif (owner = path[%r{app/(?:controllers|mailers)/(.+?)(?:_controller)?\.rb\z}, 1])
      owner.tr("/", ".")
    end
  end

  # The source that can load a unit's locale files. brgen's engines mount only in
  # brgen, and shared's keys are read by all three apps.
  def sources_for(unit)
    trees = case unit
            when "shared" then %w[brgen amber bsdports shared]
            when %r{\Abrgen(?:/|\z)} then %w[brgen shared]
            else [unit, "shared"]
            end
    @sources ||= {}
    @sources[trees] ||= trees.flat_map { |tree| Dir.glob(File.join(ROOT, tree, "**/*.{rb,erb,js,rake,jbuilder,yml,json}")) }
                             .reject { |path| path.match?(READER_SKIP) }
                             .to_h { |path| [rel(path), File.read(path)] }
  end

  READER_SKIP = %r{/(?:test|vendor|node_modules|tmp|log|storage|coverage)/|/public/assets/|/config/locales/}

  # Keys both locales declare whose %{} names differ, one line each.
  def interpolation_mismatches(en, nb)
    placeholders = ->(text) { text.to_s.scan(/%\{(\w+)\}/).flatten.uniq.sort }
    (en.keys & nb.keys).sort.filter_map do |key|
      want = placeholders.call(en[key])
      got = placeholders.call(nb[key])
      "#{key}: en #{want.inspect}, nb #{got.inspect}" unless want == got
    end
  end

  def locale_paths(app, locale)
    pattern = app == "shared" ? "shared/config/locales/*.#{locale}.yml" : "#{app}/config/locales/*#{locale}.yml"
    Dir.glob(File.join(ROOT, pattern)).sort
  end

  def keys_for(app, locale)
    locale_paths(app, locale).flat_map { |path| flat_keys(path) }.uniq
  end

  # Sorted, so a key with two homes takes the value Rails renders.
  def values_for(app, locale)
    locale_paths(app, locale).each_with_object({}) { |path, out| out.merge!(flat_values(path)) }
  end

  # The files Rails merges into one store, keyed by the app that owns the directory
  # and the locale the filename claims. Sorted, because that is the order I18n
  # loads them in and therefore which definition of a repeated key survives.
  def locale_groups
    locale_files.sort.group_by do |path|
      [rel(File.dirname(path)).sub(%r{/config/locales\z}, ""), File.basename(path, ".yml").split(".").last]
    end
  end

  def flat_values(path, node = nil, prefix = [], out = {})
    node ||= (YAML.safe_load_file(path, aliases: true) || {}).values.first || {}
    node.each do |key, value|
      path_keys = prefix + [key.to_s]
      value.is_a?(Hash) ? flat_values(path, value, path_keys, out) : out[path_keys.join(".")] = value
    end
    out
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
