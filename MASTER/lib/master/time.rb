# frozen_string_literal: true

module Master
  # One clock seam for wall-clock observations. Production uses the real clock;
  # tests can replace these methods without stubbing Ruby's global Time.
  module Time
    module_function

    def now = ::Time.now
    def utc_now = ::Time.now.utc
    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def sleep(seconds) = Kernel.sleep(seconds)
  end
end
