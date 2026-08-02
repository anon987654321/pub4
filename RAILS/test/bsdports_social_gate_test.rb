# frozen_string_literal: true

require "minitest/autorun"

# bsdports subclasses the shared social controllers (ReactionsController <
# Shared::ReactionsController) but its schema has none of the tables those
# controllers query. The route that would reach them is deliberately behind
# `if ENV["BSDPORTS_SOCIAL"] == "1"`, so on the running box (the flag is unset in
# every /etc/*.env) nothing dispatches there and there is no live 500.
#
# That safety is a coupling — a gated route AND an absent table — and a coupling
# with nothing pinning it drifts. This asserts the two halves stay in agreement:
# while bsdports lacks the reactions table, the social routes must stay gated. The
# day someone lands the migration, `test_the_gate_matches_the_schema` flips and
# tells them the gate can open. Until then, deleting the `if` without the table is
# what this catches.
class BsdportsSocialGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ROUTES = File.read(File.join(ROOT, "bsdports/config/routes.rb"))
  SCHEMA = File.read(File.join(ROOT, "bsdports/db/schema.rb"))

  SOCIAL_TABLES = %w[reactions notifications review_cases].freeze

  def has_table?(name) = SCHEMA.include?(%(create_table "#{name}"))

  def social_routes_gated?
    # The social route file is loaded only inside the ENV["BSDPORTS_SOCIAL"] guard,
    # never at the top level of the router.
    ROUTES.match?(/if\s+ENV\[["']BSDPORTS_SOCIAL["']\]\s*==\s*["']1["'].*?social\.rb.*?end/m)
  end

  def social_routes_ungated?
    # An instance_eval of social.rb that is not the guarded one.
    ROUTES.lines.any? do |line|
      line.include?("social.rb") &&
        !ROUTES[/if\s+ENV\[["']BSDPORTS_SOCIAL["'].*?#{Regexp.escape(line.strip)}.*?end/m]
    end
  end

  def test_bsdports_has_no_social_tables_yet
    SOCIAL_TABLES.each do |t|
      refute has_table?(t),
             "bsdports now has #{t}; update bsdports_social_gate_test — the gate may open"
    end
  end

  def test_social_routes_stay_gated_while_tables_are_absent
    return if SOCIAL_TABLES.all? { |t| has_table?(t) }

    assert social_routes_gated?,
           "bsdports/config/routes.rb must load shared/config/routes/social.rb only " \
           "inside `if ENV[\"BSDPORTS_SOCIAL\"] == \"1\"` while the reactions/notifications/" \
           "review_cases tables are absent — ungating it 500s ReactionsController"
    refute social_routes_ungated?,
           "social.rb is instance_eval'd outside the BSDPORTS_SOCIAL guard"
  end

  def test_the_gate_matches_the_schema
    # A living reminder: when all three tables exist, the coupling is satisfied and
    # this test (and the gate) can be retired. Fails loudly at that transition.
    all_present = SOCIAL_TABLES.all? { |t| has_table?(t) }
    refute all_present,
           "bsdports has all social tables now — drop the BSDPORTS_SOCIAL gate in routes.rb " \
           "and delete this test"
  end
end
