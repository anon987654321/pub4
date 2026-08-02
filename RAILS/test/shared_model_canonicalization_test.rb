# frozen_string_literal: true

require "minitest/autorun"

# The social models live in two layers and the rule for which one wins is real but
# was never written down in one place:
#
#   * ::Reaction and ::Notification — brgen defines app-local canonical classes.
#     Every app that does NOT is meant to fall back to Shared::Reaction /
#     Shared::Notification. The choice is made by `defined?(::X) ? ::X : Shared::X`
#     at three resolver sites (reaction_toggle.rb, notifications_controller.rb,
#     notifiable.rb). A bare `Shared::Reaction.where(...)` anywhere else would pin
#     the fallback and silently bypass brgen's canonical class — a real bug that no
#     boot-time error would surface, since both classes load fine.
#
#   * ReviewCase — no app defines ::ReviewCase, so Shared::ReviewCase IS canonical.
#     Bare use of it is correct and expected; it has no app-local twin to shadow.
#
# This test pins that split: Shared::Reaction / Shared::Notification, used AS the
# model constant, must sit on a line (or the guard line just above) that names
# `defined?`. Shared::ReviewCase is deliberately unpoliced. Names that merely start
# with the same prefix (Shared::ReactionToggle, Shared::NotificationsController) are
# not the model and are excluded by the trailing-word-boundary in the pattern.
class SharedModelCanonicalizationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The model constant exactly — not ReactionToggle, not ReactionsController.
  RESOLVED = {
    "Shared::Reaction" => /Shared::Reaction(?![A-Za-z0-9_])/,
    "Shared::Notification" => /Shared::Notification(?![A-Za-z0-9_])/,
  }.freeze

  # Where the model class itself is declared — the `class Reaction` line naturally
  # has no `defined?` and must not be flagged.
  DEFINITION_FILES = %w[
    shared/app/models/shared/reaction.rb
    shared/app/models/shared/notification.rb
  ].freeze

  def sources
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/app/**/*.rb")).sort
  end

  def test_the_canonical_resolver_is_the_only_path_to_the_fallback_model
    unguarded = []

    sources.each do |path|
      rel = path.sub("#{ROOT}/", "")
      next if DEFINITION_FILES.include?(rel)

      lines = File.readlines(path)
      lines.each_with_index do |line, i|
        next if line.strip.start_with?("#") # a comment naming the class is not a use

        RESOLVED.each do |name, pattern|
          next unless line.match?(pattern)

          # Guarded if `defined?` is on this line (single-line ternary) or the line
          # immediately above (multi-line `elsif defined?(...)` / `if defined?`).
          guard_here = line.include?("defined?")
          guard_above = i.positive? && lines[i - 1].include?("defined?")
          next if guard_here || guard_above

          unguarded << "#{rel}:#{i + 1}: bare #{name} — resolve via `defined?(::#{name.split("::").last})` instead"
        end
      end
    end

    assert_empty unguarded,
                 "these bypass the canonical app-local model:\n  #{unguarded.join("\n  ")}"
  end

  def test_the_three_resolver_sites_still_exist
    # If a refactor moves the resolver, update this list — its point is that the
    # `defined?(::X)` decision lives in a known, small set of places, not scattered.
    {
      "shared/app/services/shared/reaction_toggle.rb" => "defined?(::Reaction)",
      "shared/app/controllers/shared/notifications_controller.rb" => "defined?(::Notification)",
      "shared/app/models/concerns/shared/notifiable.rb" => "defined?(::Notification)",
    }.each do |rel, needle|
      body = File.read(File.join(ROOT, rel))
      assert_includes body, needle, "#{rel} lost its canonical resolver (#{needle})"
    end
  end
end
