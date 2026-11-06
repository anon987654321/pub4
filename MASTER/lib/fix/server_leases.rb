# frozen_string_literal: true

require "fileutils"

module Master
  module Fix
    # The app servers this process booted and owns. bin/master's TERM and INT traps end in exit!, which
    # runs no ensure and no at_exit, so a /fix run stopped mid-pass left its apps serving for hours (an
    # amber puma for five, a master server for six). The traps and an at_exit hook stop the leases held
    # here; a lease file beside each pid file names the owning process, so the wrapper that outlives a
    # run can stop the servers of one that died past both. A lease already released stops nothing, so
    # one is never dropped from the list: stop_owned! on it answers [] at once.
    module ServerLeases
      OWNER_SUFFIX = ".owner"

      @held = []

      module_function

      # A lease (anything answering stop_owned!) that now owns the server whose pid sits in pid_path.
      def hold(lease, pid_path:, pid:)
        File.write("#{pid_path}#{OWNER_SUFFIX}", "#{Process.pid} #{pid}\n")
        @held << lease unless @held.include?(lease)
        @exit_hook ||= at_exit { stop_all! }
      end

      def held = @held.dup

      def stop_all!
        held.each(&:stop_owned!)
      end

      # Callable from a signal trap, where a Mutex cannot be taken: the stop runs on its own thread.
      def stop_all_from_trap!(wait_s: 10)
        Thread.new { stop_all! }.join(wait_s)
      end

      # The servers whose owning process is gone, stopped; returns their app names. A lease whose pid
      # file is gone or names another pid is stale and only removed: that server is not the dead run's.
      def reap_orphans!(run_dir, alive: method(:alive?), killer: ->(pid) { Process.kill("TERM", -pid) })
        Dir.glob(File.join(run_dir, "*.pid#{OWNER_SUFFIX}")).filter_map do |lease|
          owner, pid = File.read(lease).split.map(&:to_i)
          next if alive.call(owner)

          reap(lease, pid:, killer:)
        end
      end

      def reap(lease, pid:, killer:)
        pid_path = lease.delete_suffix(OWNER_SUFFIX)
        FileUtils.rm_f(lease)
        return unless File.file?(pid_path) && File.read(pid_path).to_i == pid

        stop_server(pid_path, pid:, killer:)
        File.basename(pid_path, ".pid")
      end

      def stop_server(pid_path, pid:, killer:)
        killer.call(pid)
      rescue Errno::ESRCH
        :already_gone
      ensure
        FileUtils.rm_f(pid_path)
      end

      def alive?(pid)
        return false unless pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
    end
  end
end
