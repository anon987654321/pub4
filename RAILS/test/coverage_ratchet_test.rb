# frozen_string_literal: true

require "minitest/autorun"

# controller_coverage_contract_test.rb and model_coverage_contract_test.rb assert
# that source files contain particular class/def strings. They never boot Rails and
# never call a method, so they pass against a body of `raise` — TODO.md
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
  # Measured 2026-08-01. Raise a number when you add tests; never lower one —
  # EXCEPT when a vertical is extracted to an engine, which is the one honest
  # reason a host count falls. brgen 15->12 controllers / 11->10 models on
  # 2026-08-02 as the five verticals moved to engines/*: those counts were basename
  # collisions — flat host tests (channels_controller, home_controller, comment, …)
  # that also matched a same-named vertical class — so extraction removed a
  # double-count, not coverage. The host classes of those names are still tested and
  # still counted; the vertical classes are counted from engines/*/app now.
  # controllers 12 -> 11 on 2026-08-12: maps controllers moved to engines/maps.
  # Check-in is still asserted from host integration tests; the engine source
  # no longer basename-collides with a host maps_places test that was never there.
  FLOORS = {
    # models 5 -> 10 on 2026-08-16: wear_log, outfit_item, packing_list,
    # planned_outfit, sustainability_metric. Writing them found three live 500s
    # — deleting an outfit you had worn, deleting an outfit you had planned, and
    # deleting a garment on a packing list all raised InvalidForeignKey, because
    # the schema had the constraint and the model declared no dependent option.
    # foreign_key_dependency_test.rb holds the remaining fifteen.
    # controllers 1 -> 2 on 2026-08-23: declutter_controller_test covers the
    # strict-loading preloads on the declutter box.
    "amber" => { "controllers" => 2, "models" => 10 },
    # models raised 10 -> 11 on 2026-08-03; the ratchet asked for it.
    # 11 -> 13 on 2026-08-12: engines/playlist got its first tests, covering
    # Playlist::Playlist and Playlist::ListeningParty. It was the only one of the
    # five verticals with no test directory at all, and the largest untested
    # surface in the tree — this ratchet already counted engines/*/app, so the
    # zero was visible here the whole time and nobody had raised it because a
    # floor of 11 does not complain about an engine sitting at nothing.
    # models 18 -> 19 on 2026-08-16. Not this branch: the test arrived with
    # main and the floor was not raised with it, which is the direction this
    # ratchet exists to catch.
    # controllers 14 -> 20 and models 19 -> 20 on 2026-08-18: conversation_pins,
    # group_conversations, crossposts, the community wiki and story replies
    # arrived with their tests, and the controller floor was already one behind
    # before any of them. models had been RED at 17 against this 19 since before
    # that day; CommunityWikiPage, CommunityWikiRevision, LinkPreview and
    # Conversation close it.
    # controllers 20 -> 21 on 2026-08-20: the marketplace kinds test covers
    # listings across jobs, housing and gigs.
    # models 22 -> 23: `5f3580ec9 hoist one-file test dirs` moved a model test
    # onto the basename this ratchet resolves, and the floor did not move with
    # it — the same direction the 19 above was caught in.
    "brgen" => { "controllers" => 21, "models" => 23 },
    # models 1 -> 8 on 2026-08-16. bsdports had one model test (user) against
    # thirteen models, and it was the smallest tree in the repo — Port, the record
    # everything else hangs off, had nothing naming it. Writing them found two
    # real defects: maintainers.name carried a unique index with no matching
    # validation, so a duplicate came back as RecordNotUnique rather than as a
    # form error, and ports_fts turned out to be absent from every schema-loaded
    # database (RAILS/test/raw_schema_objects_test.rb).
    "bsdports" => { "controllers" => 2, "models" => 8 },
  }.freeze

  # The app's own app/ dir, plus any mounted vertical engines (engines/*/app).
  # A vertical extracted to an engine keeps its controllers/models under
  # engines/<name>/app, so counting only app/ would silently drop them and read
  # the extraction as a coverage regression. See ENGINES.md.
  def source_roots(app, kind)
    [File.join(ROOT, app, "app", kind)] + Dir.glob(File.join(ROOT, app, "engines/*/app", kind))
  end

  # Concerns are mixed into the classes above and tested through them;
  # ApplicationController/ApplicationRecord are framework glue.
  def sources(app, kind)
    source_roots(app, kind).flat_map { |root| Dir.glob(File.join(root, "**", "*.rb")) }
       .reject { |path| path.end_with?("application_controller.rb", "application_record.rb") }
       .reject { |path| path.include?("/concerns/") }
  end

  # test/controllers/marketplace/orders_controller_test.rb for
  # app/controllers/marketplace/orders_controller.rb, or the flat basename — both
  # conventions are in use in this tree. For an engine source the test lives beside
  # the engine (engines/tv/test/models/...), so resolve relative to the source's own
  # root rather than assuming the host app/.
  def tested?(app, kind, path)
    root = source_roots(app, kind).find { |r| path.start_with?("#{r}/") }
    return false unless root

    base = root.sub(%r{/app/#{Regexp.escape(kind)}\z}, "")
    rel = path.sub("#{root}/", "").sub(/\.rb\z/, "")
    [
      File.join(base, "test", kind, "#{rel}_test.rb"),
      File.join(base, "test", kind, "#{File.basename(rel)}_test.rb"),
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
