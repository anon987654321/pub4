# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../tools/code_reach"

# The census is the easy half; not being wrong is the hard half.
#
# Written three times before it was right. The first version whitelisted file
# extensions and could not see `bin/cli` or the Rakefile, so two live files read
# as dead. The second excluded ":" from its lookbehind, so every caller writing
# `Ground::BootChecks` was invisible and the whole tree read as dead — the same
# shape TODO.md records for a `\b` after a predicate's `?` and for a lookbehind
# that excluded ".". Both traps are fixtures here, because a census that cannot
# see a reference is worse than no census: it reports work to do that is not
# there, and this one's action is deletion.
class TestCodeReach < Minitest::Test
  Tool = Operator::CodeReach

  def with_bodies(files)
    Tool.instance_variable_set(:@bodies, files)
    yield
  ensure
    Tool.remove_instance_variable(:@bodies) if Tool.instance_variable_defined?(:@bodies)
  end

  def lib_path(name) = File.join(Tool::MASTER_DIR, "lib", name)

  def test_a_constant_named_only_in_qualified_form_is_reached
    subject = lib_path("ground/boot_checks.rb")

    with_bodies({ "/repo/MASTER/lib/boot/master_boot.rb" => "      Ground::BootChecks.run(root:)\n" }) do
      assert Tool.reached?(subject, "BootChecks"),
             "a lookbehind that excludes ':' hides every qualified use, which is the whole corpus"
    end
  end

  def test_a_longer_constant_that_merely_contains_the_name_is_not_a_reference
    subject = lib_path("ground/boot_checks.rb")

    with_bodies({ "/repo/MASTER/lib/other.rb" => "PreBootChecksReport = 1\n" }) do
      refute Tool.reached?(subject, "BootChecks")
    end
  end

  # bin/cli has no extension, so an extension whitelist drops it and the file it
  # requires reads as unreached.
  def test_a_reference_from_an_extensionless_executable_counts
    subject = lib_path("cli/web_server.rb")

    with_bodies({ "/repo/MASTER/bin/cli" => %(require "cli/web_server"\n) }) do
      assert Tool.reached?(subject, "WebServer")
    end
  end

  def test_a_file_named_nowhere_is_unreached
    subject = lib_path("ground/nothing_names_this.rb")

    with_bodies({ "/repo/MASTER/lib/other.rb" => "puts 1\n" }) do
      refute Tool.reached?(subject, "NothingNamesThis")
    end
  end

  # The census's own corpus, not a fixture: an extension filter here is the
  # first bug again, and it cannot be caught by a unit test of `reached?`.
  def test_the_corpus_carries_files_that_have_no_extension
    assert Tool.tracked.any? { |path| File.extname(path).empty? },
           "a corpus of only recognised extensions cannot see bin/ or the Rakefile"
  end

  def test_the_ceiling_is_recorded_with_its_members
    assert_kind_of Integer, Tool.ceiling
    assert_kind_of Array, Tool.recorded_members
  end

  # The claim the row makes today, and the one that pays for the spine budget
  # being unpayable by deletion.
  def test_no_file_in_lib_is_unreached
    assert_empty Tool.unreached
  end
end
