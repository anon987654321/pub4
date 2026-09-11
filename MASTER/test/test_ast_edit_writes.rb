# frozen_string_literal: true

require_relative "test_helper"

# The write tool could not write.
#
# AstEdit includes Io::AtomicWrite, which defines `write_atomic`. Both of its
# call sites asked for `atomic_write` — the same two words the other way round —
# so every rename and every insertion raised NoMethodError at the moment it was
# about to change a file. Nothing in the suite named AstEdit, so the tool was
# untested and the misspelling survived.
#
# The interesting half is that it fails late. Both methods validate, ask the
# governor for permission, and take an undo snapshot before they write, so a
# caller saw the tool accept the work and then die on the last line. An undo
# snapshot of a file that was never modified is the residue that was left.
class TestAstEditWrites < Minitest::Test
  # AstEdit takes an undo recorder and snapshots before writing; this is the
  # smallest thing that satisfies that contract without a real undo stack.
  class RecordingUndo
    attr_reader :snapshots

    def initialize = @snapshots = []
    def snapshot(path) = @snapshots << path
  end

  def with_ruby_file
    Dir.mktmpdir do |raw|
      # realpath, because PathGuard realpaths the file and compares against the
      # root as given. On macOS /var is a symlink to /private/var, so a bare
      # mktmpdir root makes every path under it look like an escape.
      root = File.realpath(raw)
      path = File.join(root, "subject.rb")
      File.write(path, "# frozen_string_literal: true\n\ndef old_name\n  :value\nend\n")
      yield root, path
    end
  end

  def test_rename_writes_the_file_it_was_asked_to_write
    with_ruby_file do |root, path|
      undo = RecordingUndo.new
      editor = Master::Io::AstEdit.new(root:, undo:)

      result = editor.call(operation: "rename_method", path: path, from: "old_name", to: "new_name")

      assert result.ok?, "rename reported: #{result.respond_to?(:error) ? result.error : result.inspect}"
      written = File.read(path)
      assert_includes written, "def new_name"
      refute_includes written, "def old_name"
      assert_equal [path], undo.snapshots, "the undo snapshot is taken before the write"
    end
  end

  def test_add_after_method_writes_the_file_it_was_asked_to_write
    with_ruby_file do |root, path|
      editor = Master::Io::AstEdit.new(root:, undo: RecordingUndo.new)

      result = editor.call(operation: "add_after", path: path, after: "old_name", code: "def added\n  :new\nend")

      assert result.ok?, "add_after reported: #{result.respond_to?(:error) ? result.error : result.inspect}"
      written = File.read(path)
      assert_includes written, "def added"
    end
  end

# A third test used to grep ast_edit.rb for its own method names, to catch the
# misspelling returning by another route. test_source_assertions refuses that
# shape and is right to: a test that greps a source file passes against a body
# of `raise`. Both tests above already fail when the method is missing — that
# is how the bug was found — so the grep was a third opinion on a question
# already answered behaviourally.
end
