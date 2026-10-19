# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "fix/design_audit"

# The design audit reads shape, so each test builds the shape on a scratch tree and asks what it reports.
class TestDesignAudit < Minitest::Test
  def audit = Master::Fix::DesignAudit

  def tree
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "lib"))
      yield root, File.join(root, "MASTER", "lib")
    end
  end

  def write(path, text = "# x\n")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  SHARED_BODY = "def one = 1\ndef two = 2\ndef three = 3\ndef four = 4\n"

  def test_two_files_of_one_name_with_the_same_methods_are_one_idea_written_twice
    tree do |root, lib|
      write(File.join(lib, "a", "proof.rb"), SHARED_BODY)
      write(File.join(lib, "b", "proof.rb"), SHARED_BODY)

      rows = audit.duplicated_modules(lib, repo_root: root)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "share 4 method names"
    end
  end

  def test_two_files_of_one_name_doing_different_things_are_left_alone
    tree do |root, lib|
      write(File.join(lib, "a", "proof.rb"), SHARED_BODY)
      write(File.join(lib, "b", "proof.rb"), "def alpha = 1\ndef beta = 2\ndef gamma = 3\ndef one = 1\n")

      assert_empty audit.duplicated_modules(lib, repo_root: root)
    end
  end

  def test_a_conventional_name_is_never_a_duplicate
    tree do |root, lib|
      write(File.join(lib, "a", "version.rb"), SHARED_BODY)
      write(File.join(lib, "b", "version.rb"), SHARED_BODY)

      assert_empty audit.duplicated_modules(lib, repo_root: root)
    end
  end

  def test_a_directory_with_one_file_beside_its_parent_module_is_lone
    tree do |_root, lib|
      write(File.join(lib, "face", "law_field.rb"))
      write(File.join(lib, "face.rb"))
      write(File.join(lib, "voice", "a.rb"))
      write(File.join(lib, "voice", "b.rb"))
      write(File.join(lib, "voice.rb"))

      rows = audit.lone_directories(lib)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "face/ holds only law_field.rb"
    end
  end

  def test_a_test_that_mostly_asserts_on_source_text_is_a_spelling_test
    tree do |root, _lib|
      checks = Array.new(6) { |i| "    assert_includes source, \"needle #{i}\"\n" }.join
      write(File.join(root, "MASTER", "test", "test_spelled.rb"),
            "def test_x\n  source = File.read(\"a.rb\")\n#{checks}end\n")

      rows = audit.spelling_tests(repo_root: root)

      assert_equal 1, rows.size
      assert_includes rows.first.message, "6 of 6 assertions"
    end
  end

  def test_a_test_that_runs_code_is_not_a_spelling_test
    tree do |root, _lib|
      body = "  source = File.read(\"a.rb\")\n  assert_includes source, \"one\"\n  assert_equal 3, Thing.call\n" \
             "  assert_equal 4, Thing.call(2)\n  assert_equal 5, Thing.call(3)\n"
      write(File.join(root, "MASTER", "test", "test_behaves.rb"), "def test_x\n#{body}end\n")

      assert_empty audit.spelling_tests(repo_root: root)
    end
  end

  def test_a_subprocess_inside_a_loop_is_reported_once_per_loop
    tree do |_root, lib|
      write(File.join(lib, "slow.rb"),
            "paths.each do |path|\n  Master::Io::Exec.capture3(\"rubocop\", path)\n" \
            "  Master::Io::Exec.capture3(\"reek\", path)\nend\nx = 1\n")

      rows = audit.spawn_in_loops(lib)

      assert_equal 1, rows.size
      assert_equal 1, rows.first.line
    end
  end

  def test_a_loop_without_a_subprocess_is_not_reported
    tree do |_root, lib|
      write(File.join(lib, "fast.rb"), "paths.each do |path|\n  puts path\nend\n")

      assert_empty audit.spawn_in_loops(lib)
    end
  end
end
