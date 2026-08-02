# frozen_string_literal: true

require "minitest/autorun"

# controller_coverage_contract_test.rb and model_coverage_contract_test.rb assert
# that source files contain particular class/def strings. They never boot Rails and
# never call a method, so they pass against a body of `raise` — OPENBSD/data/debt.yml
# calls them tautological and it is right. What they cannot express is the number
# that matters: how much of each app has a test at all.
#
# This is that number, as a ratchet. It cannot make anyone write a test, but it makes
# the count visible, stops it falling, and fails when it has risen and the floor was
# not raised with it — the same contract as MASTER's rake lint:spine and the
# chrome_i18n_lint baselines.
#
# Deliberately not a percentage: a percentage moves when someone deletes a
# controller, which is not coverage improving.
class CoverageRatchetTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze
  KINDS = %w[controllers models].freeze

  # app => { kind => number of sources with a matching *_test.rb }
  # Measured 2026-08-01. Raise a number when you add tests; never lower one.
  FLOORS = {
    "amber" => { "controllers" => 1, "models" => 5 },
    "brgen" => { "controllers" => 14, "models" => 11 },
    "bsdports" => { "controllers" => 2, "models" => 1 },
  }.freeze

  # Concerns are mixed into the classes above and tested through them;
  # ApplicationController/ApplicationRecord are framework glue.
  def sources(app, kind)
    Dir.glob(File.join(ROOT, app, "app", kind, "**", "*.rb"))
       .reject { |path| path.end_with?("application_controller.rb", "application_record.rb") }
       .reject { |path| path.include?("/concerns/") }
  end

  # test/controllers/marketplace/orders_controller_test.rb for
  # app/controllers/marketplace/orders_controller.rb, or the flat basename — both
  # conventions are in use in this tree.
  def tested?(app, kind, path)
    rel = path.sub("#{File.join(ROOT, app, "app", kind)}/", "").sub(/\.rb\z/, "")
    [
      File.join(ROOT, app, "test", kind, "#{rel}_test.rb"),
      File.join(ROOT, app, "test", kind, "#{File.basename(rel)}_test.rb"),
    ].any? { |candidate| File.file?(candidate) }
  end

  def counted(app, kind) = sources(app, kind).count { |path| tested?(app, kind, path) }

  def test_coverage_never_falls_below_the_recorded_floor
    regressions = APPS.flat_map do |app|
      KINDS.filter_map do |kind|
        floor = FLOORS.fetch(app).fetch(kind)
        count = counted(app, kind)
        "#{app}/#{kind}: #{count} tested, floor #{floor}" if count < floor
      end
    end

    assert_empty regressions,
                 "a test file was deleted or renamed away from its subject:\n  #{regressions.join("\n  ")}"
  end

  def test_the_floor_is_current
    stale = APPS.flat_map do |app|
      KINDS.filter_map do |kind|
        floor = FLOORS.fetch(app).fetch(kind)
        count = counted(app, kind)
        "#{app}/#{kind}: #{count} tested, floor still #{floor}" if count > floor
      end
    end

    assert_empty stale, "raise these floors in coverage_ratchet_test.rb:\n  #{stale.join("\n  ")}"
  end

  # The point of recording it: most of this tree has no test naming its subject, and
  # the string-matching contracts read as if it were covered.
  def test_the_gap_is_stated_rather_than_implied
    untested = APPS.to_h do |app|
      [app, KINDS.sum { |kind| sources(app, kind).size - counted(app, kind) }]
    end

    # Not an assertion about the number — an assertion that the number is knowable
    # from here, so a reader of the coverage contracts can find the truth.
    untested.each_value { |count| assert_kind_of Integer, count }
    assert_operator untested.values.sum, :>, 0,
                    "if this ever fails, every controller and model has a test — delete this test"
  end
end
