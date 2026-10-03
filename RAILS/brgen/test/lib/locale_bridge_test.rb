# frozen_string_literal: true

require "test_helper"

# brgen serves 31 city domains from one codebase, so LocaleBridge decides which
# shipped locale a visitor actually gets. A miscategorised language here silently
# ships the wrong interface to a whole country.
#
# Two locales ship as of 2026-08-25, not five. de.yml, fr.yml and nl.yml held
# five keys each against en.yml's 1579, so eleven domains rendered five
# translated words and 1574 English ones; they are deleted rather than kept
# unrouted, because a locale file nothing loads is inert config. The assertions
# that used to require :de and :fr are inverted below and say why — the
# behaviour reversed on purpose, and a test that quietly changed sides would
# make that indistinguishable from a regression.
class LocaleBridgeTest < ActiveSupport::TestCase
  SHIPPED = %i[nb en].freeze

  test "supported locales resolve to themselves" do
    SHIPPED.each { |locale| assert_equal locale, Brgen::LocaleBridge.resolve(locale) }
  end

  test "polish falls back to english, not french" do
    # pl was listed under ROMANCE, so wrsawa.pl served a French interface.
    assert_equal :en, Brgen::LocaleBridge.resolve(:pl)
  end

  test "nordic languages fall back to bokmal" do
    %i[da sv fi is].each { |locale| assert_equal :nb, Brgen::LocaleBridge.resolve(locale) }
  end

  # Was :fr. mlan.it and lisbon.pt were served French chrome under a rule that
  # mapped them to "the nearest available Romance locale", which is the same
  # mistake the Polish note records — narrowed at the time rather than dropped.
  # French on an Italian city is not nearer than English.
  test "romance languages fall back to english now that french does not ship" do
    %i[it pt fr fr-BE].each { |locale| assert_equal :en, Brgen::LocaleBridge.resolve(locale) }
  end

  # Was :de for the Swiss and Liechtenstein variants, and :nl for Dutch.
  test "germanic languages fall back to english now that german and dutch do not ship" do
    %i[de de-CH de-LI nl].each { |locale| assert_equal :en, Brgen::LocaleBridge.resolve(locale) }
  end

  test "unknown locales fall back to english" do
    assert_equal :en, Brgen::LocaleBridge.resolve(:xx)
  end

  # The invariant that outlives any particular locale set: no city may resolve to
  # something brgen does not ship, whatever the shipped set becomes.
  test "every registry locale resolves to a shipped locale" do
    Brgen::DomainRegistry::ENTRIES.each do |entry|
      resolved = Brgen::LocaleBridge.resolve(entry.locale)
      assert_includes SHIPPED, resolved,
                      "#{entry.domain} claims #{entry.locale.inspect} and LocaleBridge sent #{resolved.inspect}"
    end
  end

  # And the other direction, which is what the stubs defeated: a shipped locale
  # must have a locale file with real content behind it, not five keys.
  test "every shipped locale has a populated locale file" do
    # init_translations first: the backend loads lazily, so reading it cold
    # reports every locale as empty, and this assertion would then pass or fail
    # on whether some earlier test had already asked for a string.
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?

    SHIPPED.each do |locale|
      keys = I18n.backend.send(:translations).fetch(locale, {})
      assert_operator keys.size, :>, 20, "#{locale} resolves but carries almost nothing"
    end
  end

  test "fallbacks name only shipped locales" do
    Brgen::LocaleBridge.fallbacks_map.each_value do |chain|
      assert_empty chain - SHIPPED, "a fallback chain names a locale that does not ship"
    end
  end

  test "denver has one apex" do
    denvers = Brgen::DomainRegistry::ENTRIES.select { |entry| entry.city == "Denver" }
    assert_equal [ "denvr.us" ], denvers.map(&:domain)
  end
end
