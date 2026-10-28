# frozen_string_literal: true

require_relative "test_helper"
require_relative "../law/detectors/structural_laws"

class TestLibRootDisciplineRule < Minitest::Test
  # "core stays lean" as a live check: new files do not land directly in lib/
  # root without a deliberate, visible decision (adding to ALLOWED_ROOT_FILES).
  def setup
    @rule = Master::Review::Scan::Laws::LibRootDisciplineLaw.new(root: Master::ROOT)
  end

  def test_flags_a_new_file_directly_in_lib_root
    path = File.join(Master::ROOT, "lib", "some_new_thing.rb")
    findings = @rule.check("", path:)

    assert_equal 1, findings.size
    assert_match(/lib\/ root/, findings.first.message)
  end

  def test_allows_known_core_files_in_lib_root
    path = File.join(Master::ROOT, "lib", "master.rb")

    assert_empty @rule.check("", path:)
  end

  def test_ignores_files_in_subdirectories
    path = File.join(Master::ROOT, "lib", "fix", "repair_loop.rb")

    assert_empty @rule.check("", path:)
  end

  def test_ignores_non_ruby_files_in_lib_root
    path = File.join(Master::ROOT, "lib", "README.md")

    assert_empty @rule.check("", path:)
  end

  # Both directions at once, against the tree rather than a fixture, because the
  # tree is where the drift happens. An allowance for a missing file is an
  # invisible hole in the check, and a root file missing from the list is the
  # deliberate decision the rule exists to force. The finding is a warning, which
  # `rake selfcheck` does not read, so this test is what holds it. rake
  # lint:autoload is the shape being copied.
  def test_the_allowance_names_lib_root_exactly
    allowed = Master::Review::Scan::Laws::LibRootDisciplineLaw::ALLOWED_ROOT_FILES
    present = Dir.glob(File.join(Master::ROOT, "lib", "*.rb")).map { |p| File.basename(p) }

    assert_equal present.sort, allowed.sort,
                 "ALLOWED_ROOT_FILES and lib/ root have drifted: a file was added without a " \
                 "decision, or an allowance outlived the file it excused"
  end
end
