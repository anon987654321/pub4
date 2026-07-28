# frozen_string_literal: true

require "minitest/autorun"

# A budget, not a ban. Rails, ActionCable and StimulusReflex all resolve host
# constants by bare name, so SessionsController and friends must exist in every
# app even when their whole body is `include Shared::Something`. Those are 4-9
# lines each and not worth chasing. Anything *substantial* appearing in two
# apps byte-for-byte is a missed extraction — see WIRING_NOTES.md for what was
# extracted in the 2026-07-28 sweep and what was deliberately left.
class AppDuplicationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze
  MAX_DUPLICATED_LINES = 12

  # amber + bsdports share a logo animation brgen has no use for; registering it
  # in the shared Stimulus baseline would ship it to all three.
  ALLOWED = ["app/javascript/controllers/jox_logo_controller.js"].freeze

  def duplicates
    by_path = Hash.new { |hash, key| hash[key] = [] }
    APPS.each do |app|
      Dir.glob(File.join(ROOT, app, "app/**/*.{rb,erb,js,scss}")).each do |path|
        by_path[path.sub("#{File.join(ROOT, app)}/", "")] << path
      end
    end

    by_path.flat_map do |relative, paths|
      next [] if ALLOWED.include?(relative)

      paths.group_by { |path| File.read(path) }
           .select { |_body, same| same.size > 1 }
           .map { |body, same| [relative, body.lines.size, same.size] }
    end
  end

  def test_no_substantial_file_is_copied_between_apps
    offenders = duplicates.select { |_relative, lines, _count| lines > MAX_DUPLICATED_LINES }

    assert_empty offenders.map { |relative, lines, count| "#{relative} (#{lines} lines x#{count})" },
                 "identical in more than one app and big enough to extract into RAILS/shared"
  end

  # If the allow-list outlives the file it excuses, drop the entry.
  def test_allow_list_entries_still_exist
    ALLOWED.each do |relative|
      assert APPS.any? { |app| File.file?(File.join(ROOT, app, relative)) },
             "#{relative} is allow-listed but no app has it"
    end
  end
end
