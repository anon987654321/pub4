# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_dsl"
require "tmpdir"
require "fileutils"

# PATH_PURPOSE is :error, and WriteGuard blocks on error, so this rule can
# refuse a write, and its exemptions matter more than most: a prefix strip that
# is a no-op outside the root would refuse every write in RAILS, OPENBSD and
# STUDIO. Both halves are pinned below — the sibling trees are out of scope,
# and an unreadable ownership file must not turn into a blanket refusal.
class TestPathPurposeRule < Minitest::Test
  # The three key forms the rule supports, one of each. The trailing slash is
  # what makes a key cover a subtree — `lib/` covers `lib/voice/speech.rb` and a
  # bare `lib` covers only a file called exactly `lib`.
  OWNERSHIP = {
    "ownership" => {
      "lib/" => "the runtime",
      "Rakefile" => "the task surface",
      "web/public/face.part*.txt" => "the generated face sources",
    },
  }.freeze

  def in_tree(ownership: OWNERSHIP)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "PATH_OWNERSHIP.yml"), ownership.to_yaml) if ownership
      yield Master::Review::Scan::Laws::PathPurposeLaw.new(root:), root
    end
  end

  def test_an_undeclared_directory_is_reported
    in_tree do |rule, root|
      found = rule.check("", path: File.join(root, "scratchpad/thing.rb")).map(&:message)

      assert_equal 1, found.size
      assert_includes found.first, "scratchpad/"
      assert_includes found.first, "PATH_OWNERSHIP.yml"
    end
  end

  def test_a_directory_key_covers_its_whole_subtree
    in_tree { |rule, root| assert_empty rule.check("", path: File.join(root, "lib/voice/speech.rb")) }
  end

  def test_an_exact_file_key_covers_that_file
    in_tree { |rule, root| assert_empty rule.check("", path: File.join(root, "Rakefile")) }
  end

  def test_a_glob_key_covers_what_it_matches
    in_tree { |rule, root| assert_empty rule.check("", path: File.join(root, "web/public/face.part1.txt")) }
  end

  # The slash is the whole difference between a key that covers a tree and one
  # that covers a single file, and it is invisible at a glance in the YAML.
  def test_a_key_without_a_trailing_slash_does_not_cover_a_subtree
    ownership = { "ownership" => { "lib" => "the runtime" } }
    in_tree(ownership:) do |rule, root|
      refute_empty rule.check("", path: File.join(root, "lib/voice/speech.rb")),
                   "`lib` covers a file named lib, not the directory — `lib/` is the covering form"
    end
  end

  # One entry covers its whole subtree, and the finding names the shallowest
  # gap. Reporting every level below it turns one missing entry into fourteen.
  def test_it_names_the_shallowest_gap_not_every_level
    in_tree do |rule, root|
      found = rule.check("", path: File.join(root, "a/b/c/d.rb")).map(&:message)

      assert_equal 1, found.size
      assert_includes found.first, "a/ has no entry"
    end
  end

  # PATH_OWNERSHIP.yml describes MASTER and says nothing about its siblings, so it cannot judge
  # them — and at :error, judging them refused every write outside MASTER.
  def test_a_path_outside_the_root_is_out_of_scope
    in_tree do |rule, _root|
      assert_empty rule.check("", path: "/somewhere/else/RAILS/app/models/user.rb"),
                   "the ownership file describes one tree and must not judge its siblings"
    end
  end

  # Fail open, deliberately: with no ownership file there is nothing to be
  # missing from, and an :error finding here would block every write in the
  # tree. Silence is the safe direction for this one.
  def test_a_missing_ownership_file_disables_the_rule_rather_than_refusing_everything
    in_tree(ownership: nil) do |rule, root|
      assert_empty rule.check("", path: File.join(root, "scratchpad/thing.rb"))
    end
  end

  def test_malformed_ownership_yaml_is_logged_rather_than_retiring_the_corpus_in_silence
    Dir.mktmpdir do |root|
      File.write(File.join(root, "PATH_OWNERSHIP.yml"), ": not yaml [")
      rule = Master::Review::Scan::Laws::PathPurposeLaw.new(root:)

      assert_empty rule.check("", path: File.join(root, "scratchpad/thing.rb"))
      logged = Master::Ground::Swallow.recent(context: "PathPurposeLaw.owned", limit: 20)
      assert logged.any? { |row| row["severity"] == "load_bearing" },
             "an unreadable ownership file must report through Swallow, or the scan looks clean"
    end
  end

  def test_test_and_vendor_paths_are_skipped
    in_tree do |rule, root|
      %w[test/thing.rb vendor/gem/lib/thing.rb tmp/thing.rb].each do |rel|
        assert_empty rule.check("", path: File.join(root, rel)), "#{rel} should be skipped"
      end
    end
  end

  def test_a_file_at_the_root_has_no_directory_to_declare
    in_tree { |rule, root| assert_empty rule.check("", path: File.join(root, "Rakefile.rb")) }
  end

  # The skip pattern wants a slash before test/, and the house lint hands the
  # rule paths relative to MASTER, so a new test file is judged by MASTER's own
  # ownership entry; without one, every new test draws a finding at commit time.
  def test_a_new_test_file_in_masters_own_tree_is_declared
    rule = Master::Review::Scan::Laws::PathPurposeLaw.new(root: Master::ROOT)

    Dir.chdir(Master::ROOT) do
      assert_empty rule.check("", path: "test/test_not_written_yet.rb")
      refute_empty rule.check("", path: "undeclared_probe_dir/thing.rb")
    end
  end
end
