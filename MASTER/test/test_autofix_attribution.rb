# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# In the shared checkout, /fix delivers only the autofix's own writes, matched by content.
class TestAutofixAttribution < Minitest::Test
  Guard = Master::Fix::AutofixGuard

  def setup = Guard.reset!
  def teardown = Guard.reset!

  def test_a_file_still_holding_the_autofix_bytes_is_this_runs
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      Guard.note_written(path)

      assert Guard.still_as_written?(path)
    end
  end

  def test_a_later_save_by_another_writer_is_not
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      Guard.note_written(path)
      File.write(path, "A = 2\n")

      refute Guard.still_as_written?(path)
    end
  end

  def test_a_file_the_autofix_never_wrote_is_not
    refute Guard.still_as_written?("/nowhere/b.rb")
  end
end
