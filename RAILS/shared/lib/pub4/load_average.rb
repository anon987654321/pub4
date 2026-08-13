# frozen_string_literal: true

module Pub4
  # Run-queue length, on the operating system this actually deploys to.
  #
  # This exists because `File.read("/proc/loadavg")` was the load guard on
  # PruneGuestUsersJob, and OpenBSD has no /proc. The read raised ENOENT, a
  # bare `rescue StandardError` returned false, and the guard reported "not
  # busy" on every tick — inert on the only machine it was written to protect,
  # and written the day after that job took the whole site down.
  #
  # So the contract here is that unknown is not zero. `.one` returns nil when
  # the load cannot be read, and every caller has to decide what nil means for
  # it, out loud. A guard that cannot see is a different thing from a guard
  # that sees an idle box, and collapsing the two is what made the last one
  # useless.
  module LoadAverage
    module_function

    # 1-minute average, or nil if it cannot be determined.
    def one = at(0)

    # 5-minute average — steadier, and what CiGuard has always gated on.
    def five = at(1)

    def at(index)
      parts = read
      return nil if parts.nil? || parts.size <= index

      value = Float(parts[index], exception: false)
      value&.finite? ? value : nil
    end

    def read
      sysctl || procfs
    end

    # The BSDs. OpenBSD prints "1.80 2.03 2.13" and macOS prints
    # "{ 7.94 4.61 3.67 }" — the braces are real, and splitting on whitespace
    # makes the first field "{", which parses as nil and takes the whole guard
    # down the unknown path on every developer machine. Pulling the numbers out
    # rather than positioning against them covers both.
    def sysctl
      numbers = `sysctl -n vm.loadavg 2>/dev/null`.scan(/\d+(?:\.\d+)?/)
      numbers.size >= 3 ? numbers.first(3) : nil
    rescue StandardError
      nil
    end

    # Linux, where the first three fields are the same three numbers.
    def procfs
      File.read("/proc/loadavg").split.first(3)
    rescue StandardError
      nil
    end
  end
end
