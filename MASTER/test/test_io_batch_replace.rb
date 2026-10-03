# frozen_string_literal: true

require_relative "test_helper"

# BatchReplace is the `replace` tool: one governed find-and-replace across a
# directory. It must stay inside the root, skip files it cannot safely edit,
# refuse per file what the write guard refuses, and never rename over a file.
class TestIoBatchReplace < Minitest::Test
  Governor = Struct.new(:answer) do
    def permit?(_name, _tier, _detail) = answer
  end

  Verdict = Struct.new(:blocked, :introduced) do
    def blocked? = blocked
  end

  Guard = Struct.new(:blocked_paths) do
    def verdict(path:, content:) = Verdict.new(blocked_paths.any? { |p| path.end_with?(p) }, [content])
  end

  def setup
    @root = File.realpath(Dir.mktmpdir("batch_replace_"))
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "old_name.rb"), "OldName = 1\n")
    File.write(File.join(@root, "lib", "notes.md"), "OldName here\n")
    File.write(File.join(@root, "lib", "image.png"), "OldName")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def replace(governor: Governor.new(Master::Result.ok("ok")), blocked: [], **args)
    tool = Master::Io::BatchReplace.new(root: @root, governor:)
    Master::Review::Scan::WriteGuard.stub(:default, Guard.new(blocked)) { tool.call(**args) }
  end

  def test_replaces_text_in_safe_extensions_only
    result = replace(old_str: "OldName", new_str: "NewName")

    assert_equal "replaced in 2 file(s)", result.value!
    assert_equal "NewName = 1\n", File.read(File.join(@root, "lib", "old_name.rb"))
    assert_equal "OldName", File.read(File.join(@root, "lib", "image.png")), "a binary extension is never edited"
  end

  def test_a_guard_refusal_skips_that_file_and_names_it
    result = replace(old_str: "OldName", new_str: "NewName", blocked: ["old_name.rb"])

    assert_match(/replaced in 1 file\(s\) — 1 refused/, result.value!)
    assert_equal "OldName = 1\n", File.read(File.join(@root, "lib", "old_name.rb"))
  end

  def test_renames_files_but_never_over_an_existing_one
    File.write(File.join(@root, "lib", "old_other.rb"), "x\n")
    File.write(File.join(@root, "lib", "new_other.rb"), "keep me\n")
    replace(old_str: "old_", new_str: "new_", rename_files: true)

    assert File.exist?(File.join(@root, "lib", "new_name.rb"))
    assert File.exist?(File.join(@root, "lib", "old_other.rb")), "a conflicting rename is left alone"
    assert_equal "keep me\n", File.read(File.join(@root, "lib", "new_other.rb"))
  end

  def test_a_directory_outside_the_root_is_refused
    result = replace(old_str: "a", new_str: "b", dir: "../elsewhere")

    assert result.err?
    assert_equal :validation, result.category
  end

  def test_the_governor_decides_before_anything_is_read
    denied = Master::Result.err("denied", category: :policy)
    result = replace(governor: Governor.new(denied), old_str: "OldName", new_str: "NewName")

    assert_same denied, result
    assert_equal "OldName = 1\n", File.read(File.join(@root, "lib", "old_name.rb"))
  end
end
