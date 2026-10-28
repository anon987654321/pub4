# frozen_string_literal: true

require "test_helper"

# The scan lock was CREAT|EXCL plus an mtime sweep: a crash held the file for
# five minutes, the sweep could delete a lock a slow scan still held, and a
# timed-out waiter's ensure deleted the holder's lock on its way out.
class ScanFileLockTest < Minitest::Test
  def setup
    @processor = Master::Fix::Scan::FileProcessor.new
    @dir = Dir.mktmpdir("scan-lock")
    @target = File.join(@dir, "subject.rb")
    File.write(@target, "x = 1\n")
  end

  def teardown = FileUtils.remove_entry(@dir)

  def lock(&) = @processor.send(:with_file_lock, @target, &)

  def test_extensionless_ruby_shebang_gets_an_ast
    path = File.join(File.dirname(@target), "doctor")
    File.write(path, "#!/usr/bin/env ruby\nclass Doctor; end\n")

    ast = @processor.send(:parse_ruby, File.read(path), path)

    refute_nil ast
  end

  def test_syntax_failure_never_repairs_the_file
    original = "def broken(  \n  value = 1   \n"
    File.write(@target, original)

    result = @processor.call(path: @target, depth: :deep, laws: [])

    assert result.ok?
    assert_equal original, File.read(@target)
  end

  def test_a_writing_fix_asks_every_clean_file_and_a_skip_still_wins
    @processor.full_semantic!
    assert @processor.send(:semantic_due?, [], "lib/fix/protocol.rb")
    @processor.skip_semantic!
    refute @processor.send(:semantic_due?, [], "lib/fix/protocol.rb")
  end

  def test_a_crashed_holder_frees_the_lock_at_once
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      lock do
        writer.puts "held"
        writer.close
        exit!(1)
      end
    end
    writer.close
    assert_equal "held\n", reader.gets
    Process.wait(pid)

    ran = false
    Timeout.timeout(2) { lock { ran = true } }
    assert ran
  end

  def test_two_scans_of_one_file_run_concurrently
    other = Master::Fix::Scan::FileProcessor.new
    stub_const_timeout(0.5) do
      lock do
        result = Thread.new { other.call(path: @target, depth: :deep, laws: []) }.value

        assert result.ok?, "a second scan waited out the first one's hold: #{result.inspect}"
        assert_empty other.semantic_gaps
      end
    end
  end

  # The sweep's exclusive probe is the one holder a scan still waits for.
  def test_a_scan_that_times_out_is_inconclusive_and_leaves_the_holder_its_lock
    lock_path = @processor.send(:lock_path_for, @target)
    FileUtils.mkdir_p(File.dirname(lock_path))
    stub_const_timeout(0.1) do
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |holder|
        holder.flock(File::LOCK_EX)
        result = Thread.new { @processor.call(path: @target, depth: :deep, laws: []) }.value

        assert result.ok?, "a lock timeout must not fail the walk: #{result.inspect}"
        gap = @processor.semantic_gaps.values.join
        assert_includes gap, "INCONCLUSIVE", "a file not measured must not read as clean"
        assert File.exist?(lock_path), "the waiter deleted the holder's lock"
      end
    end
  end

  private

  def stub_const_timeout(seconds)
    klass = Master::Fix::Scan::FileProcessor
    original = klass::LOCK_TIMEOUT
    klass.send(:remove_const, :LOCK_TIMEOUT)
    klass.const_set(:LOCK_TIMEOUT, seconds)
    yield
  ensure
    klass.send(:remove_const, :LOCK_TIMEOUT)
    klass.const_set(:LOCK_TIMEOUT, original)
  end
end
