# frozen_string_literal: true

require "minitest/autorun"

# A DELETE that cannot be taken back asks first. Every such control in the four
# apps already does — measured 2026-09-13, 25 confirmed of 25 — so this is a
# guard on a mechanism that exists and nothing watched.
#
# Irreversible is read from the label's I18n key, because that is what the
# visitor reads: a key naming delete, unsend or a permanent removal. The other
# DELETE-method controls are toggles with an undo one tap away — unfollow,
# unsave, unlike, unwatch, sign out, remove from a plan — and a confirmation in
# front of a toggle is friction, not safety.
class DestructiveConfirmationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  DELETE_METHOD = /method: :delete|turbo_method: :delete/
  IRREVERSIBLE_KEY = /(?:\A|[._])(?:delete|delete_permanent|unsend|remove_listing|end_party|unmatch|group_leave)\z/

  def views
    %w[amber brgen bsdports shared].flat_map do |app|
      Dir.glob(File.join(ROOT, app, "app/views/**/*.erb")) +
        Dir.glob(File.join(ROOT, app, "engines/*/app/views/**/*.erb"))
    end.sort
  end

  # The helper call a DELETE option belongs to: back to its button_to/link_to,
  # forward to the ERB close, since the options wrap onto following lines.
  def delete_calls(path)
    lines = File.readlines(path)
    lines.each_index.select { |i| lines[i].match?(DELETE_METHOD) }.map do |i|
      start = i
      start -= 1 while start.positive? && !lines[start].match?(/button_to|link_to/)
      call = lines[start..[i + 4, lines.size - 1].min].join
      [start + 1, call[0, call.index("%>") || call.size]]
    end
  end

  def test_irreversible_deletes_ask_for_confirmation
    checked = 0
    unconfirmed = views.flat_map do |path|
      delete_calls(path).filter_map do |line, call|
        key = call[/t\(\s*"([^"]+)"/, 1].to_s
        next unless key.match?(IRREVERSIBLE_KEY)

        checked += 1
        "#{path.delete_prefix("#{ROOT}/")}:#{line} #{key}" unless call.include?("confirm")
      end
    end

    assert_operator checked, :>=, 20, "the scan found almost no destructive controls — the glob or key pattern is wrong"
    assert_empty unconfirmed, "An irreversible DELETE with no turbo_confirm:\n#{unconfirmed.join("\n")}"
  end
end
