# frozen_string_literal: true

# Every scan rule that carries worked examples must satisfy them.
#
# Across seven categories audited in RAILS/FINAL_TODO.md, six failed the same
# way: the rule matched a pattern adjacent to the law it enforced.
#
#   TIME_ZONE_UNSAFE     matched Time.now; the law is about Time.zone, and
#                        Time.now.utc / Time.now.to_i read neither.
#   rb_long_method       counted the start..end span; the law is about how much
#                        logic a method holds, so it penalised comments.
#   css_px_width         read an @media condition as an element width.
#   target_no_controller knew one of the three ways a controller registers.
#
# Every one of those is a false *positive*: the rule fires where the law is
# satisfied. A rule that carries the case it must not fire on cannot drift that
# way in silence, which is why does_not_fire matters more here than fires.
#
# Add examples to a rule with RuleDSL.rule(..., fires:, does_not_fire:).

require_relative "test_helper"
# rule_dsl.rb requires every rules/*.rb at the bottom, and each RuleDSL.rule call
# registers through Rule.inherited. Without this the registry is empty and the
# two assertions below pass having checked nothing.
require_relative "../lib/review/scan/rule_dsl"

class TestRuleFixtures < Minitest::Test
  Rule = Master::Review::Scan::Rule

  # `html` is what the web rules declare in applies_to:, and it was missing, so
  # every one of them fell through to the ruby path — a view rule guarded by
  # `path.include?("/app/views/")` could not fire on its own worked example, and
  # the only way to give it one was to spell example_path by hand.
  DEFAULT_PATHS = {
    ruby: "/repo/app/models/example.rb",
    scss: "/repo/app/assets/stylesheets/_example.scss",
    css: "/repo/app/assets/stylesheets/example.css",
    html: "/repo/app/views/example.html.erb",
    erb: "/repo/app/views/example.html.erb",
    js: "/repo/app/javascript/controllers/example_controller.js",
  }.freeze

  def self.fixtured
    @fixtured ||= Rule.registry.select do |klass|
      klass.respond_to?(:dsl_fires) && (klass.dsl_fires || klass.dsl_does_not_fire)
    end
  end

  def rule_id(klass)
    klass.new.id
  rescue StandardError
    klass.name.to_s
  end

  def example_path(klass)
    return klass.dsl_example_path if klass.dsl_example_path

    lang = Array(klass.dsl_langs).first
    DEFAULT_PATHS.fetch(lang&.to_sym, DEFAULT_PATHS[:ruby])
  end

  def findings_for(klass, source)
    klass.new.check(source, path: example_path(klass)) || []
  end

  def test_each_fixtured_rule_fires_on_its_positive_example
    failures = self.class.fixtured.filter_map do |klass|
      next unless klass.dsl_fires

      found = findings_for(klass, klass.dsl_fires)
      "#{rule_id(klass)} did not fire on its own fires: example" if found.empty?
    end

    assert_empty failures, failures.join("\n")
  end

  # The direction that actually breaks.
  def test_no_fixtured_rule_fires_on_its_negative_example
    failures = self.class.fixtured.filter_map do |klass|
      next unless klass.dsl_does_not_fire

      found = findings_for(klass, klass.dsl_does_not_fire)
      next if found.empty?

      "#{rule_id(klass)} fired on its does_not_fire: example — #{found.map { |f| f[:message] }.first(2).join('; ')}"
    end

    assert_empty failures, failures.join("\n")
  end

  # A harness that silently stops finding rules passes forever.
  def test_the_harness_still_sees_rules
    assert_operator Rule.registry.size, :>, 100,
                    "only #{Rule.registry.size} rules registered — the registry stopped loading"
    assert_operator self.class.fixtured.size, :>=, 2,
                    "only #{self.class.fixtured.size} rules carry examples — fixtures stopped being read"
  end
  # The other 89: rules with NO worked example at all. A law cannot load
  # without fixtures; a registry rule can, and that gap is where the twin
  # campaign found every silent drift. This ceiling only moves down — a new
  # rule must carry fires:/does_not_fire:, and adding examples to an old one
  # lowers the recorded number by hand (data/rules.yml, rule_ratchets.fixture_debt).
  def test_the_unfixtured_registry_only_shrinks
    unfixtured = Rule.registry.reject do |klass|
      (klass.respond_to?(:dsl_fires) && (klass.dsl_fires || klass.dsl_does_not_fire)) ||
        !klass.respond_to?(:dsl_block)
    end
    ceiling = Master.law("rule_ratchets").fetch("fixture_debt").fetch("without_fixtures")
    assert_operator unfixtured.size, :<=, ceiling,
      "a new registry rule without fires:/does_not_fire: — carry the worked examples, the way every law must"
    return unless unfixtured.size < ceiling
    puts "rule_fixture_debt: #{unfixtured.size} < ceiling #{ceiling} — record the new low in data/rules.yml rule_ratchets.fixture_debt"
  end

end
