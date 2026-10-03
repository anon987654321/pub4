# frozen_string_literal: true

require "test_helper"

# The scan lock was CREAT|EXCL plus an mtime sweep: a crash held the file for
# five minutes, the sweep could delete a lock a slow scan still held, and a
# timed-out waiter's ensure deleted the holder's lock on its way out.
class ScanFileLockTest < Minitest::Test
  def setup
    @processor = Master::Review::Scan::FileProcessor.new
    @target = File.join(Dir.mktmpdir("scan-lock"), "subject.rb")
    File.write(@target, "x = 1\n")
  end

  def lock(&) = @processor.send(:with_file_lock, @target, &)

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

  def test_a_waiter_that_times_out_leaves_the_holder_its_lock
    lock_path = @processor.send(:lock_path_for, @target)
    stub_const_timeout(0.1) do
      lock do
        waiter = Thread.new do
          other = Master::Review::Scan::FileProcessor.new
          assert_raises(RuntimeError) { other.send(:with_file_lock, @target) { flunk "entered a held lock" } }
        end
        waiter.join
        assert File.exist?(lock_path), "the waiter deleted the holder's lock"
      end
    end
  end

  private

  def stub_const_timeout(seconds)
    klass = Master::Review::Scan::FileProcessor
    original = klass::LOCK_TIMEOUT
    klass.send(:remove_const, :LOCK_TIMEOUT)
    klass.const_set(:LOCK_TIMEOUT, seconds)
    yield
  ensure
    klass.send(:remove_const, :LOCK_TIMEOUT)
    klass.const_set(:LOCK_TIMEOUT, original)
  end
end
