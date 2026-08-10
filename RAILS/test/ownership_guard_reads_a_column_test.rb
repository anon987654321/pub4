# frozen_string_literal: true

require "minitest/autorun"

# An ownership guard must compare a column, not an association.
#
# brgen's ownership_guard_contract_test already asserts that every mutating
# controller *has* a guard. It accepts `Current.user ==` as proof of one — and
# that is the shape which does not work:
#
#   @track = Playlist::Track.find(params[:id])   # nothing preloaded
#   return if @track.user == Current.user        # raises here
#
# ApplicationRecord sets strict_loading_by_default in every environment, so the
# association read raises StrictLoadingViolationError before the comparison
# happens. The guard does not deny access. It never runs, and every path behind
# it fails — for the owner as much as for anyone else.
#
# The two tests are complements, and neither replaces the other: one asks
# whether a guard is present, this one asks whether it can execute. Seven
# controllers carried the broken shape when it was first swept on 2026-08-10,
# which is what a present-but-non-functioning guard buys you.
#
# `record.user_id == Current.user&.id` is immune: a column is on the row the
# finder already loaded, so there is nothing to lazily load and nothing to
# raise. It also needs no `includes`, which is why it is the fix rather than
# preloading every guarded record.
class OwnershipGuardReadsAColumnTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  GUARD_METHOD = /^\s*def\s+\w*(?:authorize|authoriz|owner|permit|can_)\w*[!?]?/

  # The risky side is the *record's* association — the object that came back
  # from a finder with nothing preloaded. `Current.user` is never risky: it is
  # already materialised by the time any guard runs, and `Current.user.id` is a
  # column read on it. Matching it was this gate's own first bug, and it flagged
  # the two fixes in this commit as violations.
  RECORD = /(?!Current\b)(?:@\w+|\b[a-z_]\w*)/
  ASSOCIATION_COMPARE = /
    #{RECORD}(?:&)?\.(?:user|owner)\b(?!_id)\s*== |
    ==\s*#{RECORD}(?:&)?\.(?:user|owner)\b(?!_id)(?!\.)
  /x

  # Records the guard can safely read, with the reason each one is safe. A bare
  # name is not enough: the point of this file is that "it looked guarded" is
  # how seven controllers shipped broken.
  PRELOADED = {
    "amber/app/controllers/posts_controller.rb" =>
      "set_post preloads :user for the Article schema on posts#show",
    "amber/app/controllers/creator_profiles_controller.rb" =>
      "@profile comes from Current.user, already materialised",
    "brgen/app/controllers/posts_controller.rb" =>
      "set_post includes :user",
    "brgen/engines/playlist/app/controllers/playlist/playlists_controller.rb" =>
      "set_playlist includes :user",
    "brgen/engines/tv/app/controllers/tv/videos_controller.rb" =>
      "set_video includes :user",
  }.freeze

  def test_no_ownership_guard_compares_an_association_object
    offenders = controllers.flat_map { |path| association_compares_in(path) }
                           .reject { |path, _line, _src| PRELOADED.key?(path) }

    assert_empty offenders.map { |path, line, src| "#{path}:#{line}  #{src}" },
                 "ownership guard(s) comparing an association object rather than its _id column.\n" \
                 "strict_loading_by_default makes the read raise before the comparison, so the guard " \
                 "never runs and the action fails for the owner too.\n" \
                 "Use `record.user_id == Current.user&.id`, or add the file to PRELOADED with the " \
                 "reason its association is already loaded."
  end

  def test_the_allowlist_still_describes_real_files
    stale = PRELOADED.keys.reject { |path| File.file?(File.join(ROOT, path)) }

    assert_empty stale,
                 "PRELOADED names files that no longer exist — an exemption whose subject is gone " \
                 "is a hole in this gate that nobody can see"
  end

  private

  def controllers
    (Dir.glob(File.join(ROOT, "{amber,brgen,bsdports}/app/controllers/**/*.rb")) +
     Dir.glob(File.join(ROOT, "brgen/engines/*/app/controllers/**/*.rb")) +
     Dir.glob(File.join(ROOT, "shared/app/controllers/**/*.rb")))
      .reject { |path| path.include?("/vendor/") }
      .map { |path| path.sub("#{ROOT}/", "") }
  end

  # Inside a guard method only: an association read in an ordinary action is an
  # N+1, not a broken authorization check, and this gate is about the latter.
  def association_compares_in(path)
    inside = false
    File.readlines(File.join(ROOT, path)).each_with_index.filter_map do |line, index|
      inside = line.match?(GUARD_METHOD) if line.match?(/^\s*def\s/)
      next unless inside
      next if line.strip.start_with?("#")
      next unless line.match?(ASSOCIATION_COMPARE)

      [path, index + 1, line.strip]
    end
  end
end
