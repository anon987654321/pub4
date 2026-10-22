# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/ground/library_verify"

# A cache keyed on the lock misses when a version moves, not when a constraint is rewritten.
class TestLockedVersions < Minitest::Test
  LOCK = <<~LOCK
    GEM
      specs:
        ruby_llm (1.9.0)
          json (< 3)
        rubocop (1.81.0)
  LOCK

  def digest_of(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "Gemfile.lock")
      File.write(path, text)
      Master::Ground::LibraryVerify.pinned_digest(path)
    end
  end

  def test_a_constraint_written_differently_keeps_the_digest
    assert_equal digest_of(LOCK), digest_of(LOCK.sub("json (< 3)", "json (< 4)"))
  end

  def test_a_moved_version_changes_the_digest
    refute_equal digest_of(LOCK), digest_of(LOCK.sub("rubocop (1.81.0)", "rubocop (1.82.0)"))
  end
end
