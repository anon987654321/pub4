# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/content_honesty"

# Faker filler on a public surface.
#
# brgen's sitemap once listed 1376 posts of which 1088 were Latin slugs —
# /posts/quis-autem-eveniet-sunt-tenetur — while release, production,
# layout_suite and the whole rendered suite passed, because every one of them
# read source and the defect was entirely in rows.
#
# The source half stops the seeders putting it back and is what these tests
# plant. The live half reads the sitemap over HTTP and reports itself
# inconclusive with nothing listening, so its detector is exercised directly
# instead: the marker list is Faker::Lorem's own wordlist rather than
# "lorem ipsum", which appears in almost no generated sentence and is why
# eyeballing missed a thousand rows.
#
# The gate resolves the seeders from constants fixed at load time, so the
# fixture is installed by rewriting ROOT and RAILS.
class ContentHonestyGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::ContentHonestyGate
  HONEST_SEED = "Post.create!(title: Brgen::PlausibleContent.title, content: Brgen::PlausibleContent.body)\n"
  FILLER_SEED = "Post.create!(title: Faker::Lorem.sentence, content: Faker::Lorem.paragraph)\n"

  def gate_over(seeds)
    Dir.mktmpdir do |dir|
      plant_apps_yml(dir, "brgen")
      GATE::SEED_SOURCES.each { |rel| plant(dir, File.join("RAILS", rel), seeds) }
      with_constants(GATE, ROOT: dir, RAILS: File.join(dir, "RAILS")) { GATE.run }
    end
  end

  def test_a_seeder_titling_a_post_from_faker_fails
    result = gate_over(FILLER_SEED)

    refute result.ok?, "a post seeded from Faker::Lorem passed"
    assert_equal GATE::SEED_SOURCES.size, result.failures.size
    assert_match(%r{brgen/db/seeds\.rb:1 seeds a post from Faker::Lorem}, result.failures.first)
    assert_match(/use Brgen::PlausibleContent/, result.failures.first)
  end

  def test_the_same_seeder_on_plausible_content_passes
    result = gate_over(HONEST_SEED)

    assert result.ok?, result.failures.join(", ")
    assert_equal GATE::SEED_SOURCES.size, result.checks_ran
  end

  # Faker is fine for a name, a city or a price. Only a title or a body is a
  # public surface, so a check that banned the library outright would be turned
  # off rather than obeyed.
  def test_faker_used_for_a_name_is_not_a_finding
    result = gate_over("User.create!(name: Faker::Name.name, city: Faker::Address.city)\n")

    assert result.ok?, result.failures.join(", ")
  end

  def test_a_missing_seeder_fails_rather_than_passing_unread
    result = Dir.mktmpdir do |dir|
      plant_apps_yml(dir, "brgen")
      with_constants(GATE, ROOT: dir, RAILS: File.join(dir, "RAILS")) { GATE.run }
    end

    refute result.ok?, "an absent seeder passed"
    assert_match(%r{missing brgen/db/seeds\.rb}, result.failures.first)
  end

  # With nothing listening the live half says so rather than claiming the
  # sitemap is clean.
  def test_the_live_half_reports_itself_unmeasured_when_nothing_is_listening
    result = gate_over(HONEST_SEED)

    assert_equal :passed, result.outcome, "the source half ran, so the gate is not inconclusive"
    assert(result.unchecked.any? { |line| line.match?(/sitemap not probed/) }, result.unchecked.join(", "))
  end

  def test_the_slug_reader_knows_faker_latin_from_norwegian
    gate = GATE.new

    assert gate.send(:latin_slug?, "https://brgen.no/posts/quis-autem-eveniet-sunt-tenetur")
    assert gate.send(:latin_slug?, "https://brgen.no/posts/necessitatibus-og-mer")
    refute gate.send(:latin_slug?, "https://brgen.no/posts/bybanen-til-asane-apner")
    refute gate.send(:latin_slug?, "https://brgen.no/posts/")
  end

  # "lorem ipsum" is the pair nobody generates. The markers are the words
  # Faker::Lorem actually emits, which is the whole reason the gate sees what a
  # reader scanning for "lorem" did not.
  def test_the_markers_are_the_generated_words_not_the_placeholder_phrase
    refute_includes GATE::MARKERS, "lorem"
    assert_includes GATE::MARKERS, "eveniet"
  end
end
