# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "tmpdir"
require_relative "../tools/data_reach"

# A census that records only an integer can say "over by two" and never which
# two. data_reach was over by exactly that on 2026-08-31 and the number had no
# thread to pull: identifying the pair meant checking out the commit that set
# the ceiling and diffing two member lists by hand. They turned out to be
# rules.yml#business_plan and rules.yml#markdown_style — the two sections
# WISHLIST 67 records as clobbered by a read-modify-write and restored without
# a reader.
#
# So the ceiling file now carries its members beside the count, and --ratchet
# seeds them at parity as well as on a fall, because requiring a fall first is a
# deadlock exactly when attribution is wanted. This holds that behaviour; the
# census itself is tested by being run, not here.
class TestDataReachAttribution < Minitest::Test
  # A file the census cannot parse has no keys, so every key in it used to pass
  # as read — an unread-declaration census reporting an unreadable file clean.
  # data/radio_bergen_track_dossiers.yml is the file that does it today.
  def test_an_unparseable_data_file_says_so_and_yields_nothing
    Dir.mktmpdir("data_reach") do |dir|
      path = File.join(dir, "broken.yml")
      File.write(path, "keys: [unclosed\n")

      _, err = capture_io { assert_nil Pub4::DataReach.document(path) }

      assert_match(/broken\.yml does not parse/, err)
      assert_match(/pass this census unread/, err)
    end
  end

  Tool = Pub4::DataReach

  # The tool reads CEILING as a frozen constant, so the seam is the constant
  # itself. Swapped and restored rather than redefined, to avoid a warning
  # storm and to leave the constant as it found it.
  def swap_ceiling(path)
    previous = Tool.const_get(:CEILING)
    Tool.send(:remove_const, :CEILING)
    Tool.const_set(:CEILING, path)
    yield
  ensure
    Tool.send(:remove_const, :CEILING)
    Tool.const_set(:CEILING, previous)
  end

  def in_tmp_ceiling(contents)
    Dir.mktmpdir("data_reach") do |dir|
      path = File.join(dir, "data_reach.yml")
      File.write(path, contents.to_yaml) if contents
      swap_ceiling(path) { yield path }
    end
  end

  def test_the_ceiling_is_still_read_from_the_count
    in_tmp_ceiling({ "unnamed" => 12 }) { assert_equal 12, Tool.ceiling }
  end

  def test_members_are_read_when_present
    in_tmp_ceiling({ "unnamed" => 2, "members" => ["a.yml#one", "b.yml#two"] }) do
      assert_equal ["a.yml#one", "b.yml#two"], Tool.recorded_members
    end
  end

  # The old format is a count and nothing else. It must keep working, and must
  # say that attribution is unavailable rather than reporting zero arrivals —
  # "nothing new" and "I cannot tell" are the two answers that must not be
  # confused.
  def test_a_count_only_ceiling_reports_no_members
    in_tmp_ceiling({ "unnamed" => 46 }) do
      assert_empty Tool.recorded_members

      out, = capture_io { Tool.send(:report_new, ["x.yml#new"]) }

      assert_match(/no members recorded/, out)
      refute_match(/arrived/, out, "it claimed an arrival count it cannot know")
    end
  end

  def test_it_names_what_arrived_and_what_left
    in_tmp_ceiling({ "unnamed" => 2, "members" => ["kept.yml#a", "gone.yml#b"] }) do
      out, = capture_io { Tool.send(:report_new, ["kept.yml#a", "new.yml#c"]) }

      assert_match(/1 arrived/, out)
      assert_match(/\+ new\.yml#c/, out)
      assert_match(/gone\.yml#b/, out)
      refute_match(/\+ kept\.yml#a/, out, "a member that was already recorded was called new")
    end
  end

  def test_a_missing_ceiling_file_is_zero_and_empty
    in_tmp_ceiling(nil) do
      assert_equal 0, Tool.ceiling
      assert_empty Tool.recorded_members
    end
  end

  def test_attributed_requires_the_yaml_basename_in_the_same_file
    Tool.instance_variable_set(:@code_files, {
      "phase.rb" => "state['success_criteria']",
      "loader.rb" => "load_yaml('rules.yml')",
    })
    refute Tool.attributed?("success_criteria", "rules.yml")

    Tool.instance_variable_set(:@code_files, {
      "rules.rb" => "Master.load_yaml('rules.yml'); data['success_criteria']",
    })
    assert Tool.attributed?("success_criteria", "rules.yml")
  ensure
    Tool.instance_variable_set(:@code_files, nil)
    Tool.instance_variable_set(:@code, nil)
  end
end
