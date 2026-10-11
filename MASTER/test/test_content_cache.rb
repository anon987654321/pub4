# frozen_string_literal: true

require_relative "test_helper"

class TestContentCache < Minitest::Test
  Cache = Master::Io::ContentCache

  def with_file(body, age: 3600)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "f.txt")
      File.write(path, body)
      past = Time.now - age
      File.utime(past, past, path)
      yield path, past
    end
  end

  def counting_hashes
    calls = 0
    original = Digest::SHA256.method(:file)
    Digest::SHA256.define_singleton_method(:file) { |*args| calls += 1 and original.call(*args) }
    yield -> { calls }
  ensure
    Digest::SHA256.define_singleton_method(:file, original)
  end

  def test_unchanged_file_is_hashed_once
    with_file("alpha\n") do |path, _|
      cache = Cache.new
      counting_hashes do |calls|
        first = cache.digest(path)
        3.times { assert_equal first, cache.digest(path) }
        assert_equal 1, calls.call
      end
    end
  end

  def test_size_change_is_never_served_stale
    with_file("alpha\n") do |path, past|
      cache = Cache.new
      before = cache.digest(path)
      File.write(path, "alpha beta\n")
      File.utime(past, past, path)

      refute_equal before, cache.digest(path)
    end
  end

  def test_same_size_same_mtime_edit_inside_the_racy_window_is_caught
    with_file("alpha\n", age: 0) do |path, _|
      cache = Cache.new
      before = cache.digest(path)
      stat = File.stat(path)
      File.write(path, "omega\n")
      File.utime(stat.atime, stat.mtime, path)

      refute_equal before, cache.digest(path)
    end
  end

  def test_forced_verify_catches_a_deliberately_reset_mtime
    with_file("alpha\n") do |path, past|
      cache = Cache.new
      before = cache.digest(path)
      File.write(path, "omega\n")
      File.utime(past, past, path)

      assert_equal before, cache.digest(path), "the mtime+size fast path trusts an old matching row"
      refute_equal before, cache.digest(path, verify: true)
      assert_equal Digest::SHA256.hexdigest("omega\n"), cache.digest(path)
    end
  end

  def test_missing_file_is_nil
    assert_nil Cache.new.digest("/nonexistent/path/xyz")
  end

  def test_truth_skips_the_hash_for_an_unchanged_read_and_still_sees_an_edit
    with_file("alpha\n") do |path, past|
      truth = Master::Ground::Truth.new
      truth.record_read!(path, content: "alpha\n")
      counting_hashes do |calls|
        3.times { refute truth.changed_since_read?(path) }
        assert_equal 0, calls.call

        File.write(path, "alpha plus\n")
        File.utime(past, past, path)
        assert truth.changed_since_read?(path)
      end
    end
  end
end
