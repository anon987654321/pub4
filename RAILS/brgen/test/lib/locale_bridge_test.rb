# frozen_string_literal: true

require "test_helper"

# brgen serves 30 city domains from one codebase, so LocaleBridge decides which
# of the five available locales a visitor actually gets. A miscategorised
# language here silently ships the wrong interface to a whole country.
class LocaleBridgeTest < ActiveSupport::TestCase
  test "supported locales resolve to themselves" do
    %i[nb en nl de fr].each do |locale|
      assert_equal locale, Brgen::LocaleBridge.resolve(locale)
    end
  end

  test "polish falls back to english, not french" do
    # pl was listed under ROMANCE, so wrsawa.pl served a French interface.
    assert_equal :en, Brgen::LocaleBridge.resolve(:pl)
  end

  test "nordic languages fall back to bokmal" do
    %i[da sv fi is].each do |locale|
      assert_equal :nb, Brgen::LocaleBridge.resolve(locale)
    end
  end

  test "romance languages fall back to french" do
    %i[it pt fr-BE].each do |locale|
      assert_equal :fr, Brgen::LocaleBridge.resolve(locale)
    end
  end

  test "germanic variants fall back to german, dutch stays dutch" do
    %i[de-CH de-LI].each { |locale| assert_equal :de, Brgen::LocaleBridge.resolve(locale) }
    assert_equal :nl, Brgen::LocaleBridge.resolve(:nl)
  end

  test "unknown locales fall back to english" do
    assert_equal :en, Brgen::LocaleBridge.resolve(:xx)
  end

  test "every registry locale resolves to a shipped locale" do
    shipped = %i[nb en nl de fr]
    Brgen::DomainRegistry::ENTRIES.each do |entry|
      resolved = Brgen::LocaleBridge.resolve(entry.locale)
      assert_includes shipped, resolved,
                      "#{entry.domain} claims #{entry.locale.inspect} and LocaleBridge sent #{resolved.inspect}"
    end
  end

  test "denver has one apex" do
    denvers = Brgen::DomainRegistry::ENTRIES.select { |entry| entry.city == "Denver" }
    assert_equal [ "denvr.us" ], denvers.map(&:domain)
  end
end
