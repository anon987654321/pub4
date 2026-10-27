# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require "time"

module Master
  module Ops
    # The single execution slot: /fix and the vm23 control plane each claim it,
    # so neither fetches, rebases or deploys while the other mutates main.
    module LoopOwner
      ROOT_DIR = File.join(Master::ROOT, ".master", "active_loop").freeze

      # Only a claim written on another host ages out: its PID cannot be probed
      # from here, so time is the one signal left. A local claim lives exactly
      # as long as its process, however long a /fix run takes.
      STALE_SECONDS = 3600

      module_function

      def dir
        value = ENV["MASTER_ACTIVE_LOOP_DIR"].to_s
        value.empty? ? ROOT_DIR : File.expand_path(value)
      end

      def info
        File.join(dir, "owner.json")
      end

      def claim(name)
        cleanup_stale!
        FileUtils.mkdir_p(File.dirname(dir))
        Dir.mkdir(dir)

        begin
          File.write(info, JSON.generate(loop: name.to_s, pid: Process.pid, host: Socket.gethostname,
                                         at: Time.now.utc.iso8601))
        rescue StandardError
          # An empty claim directory would hold the slot with no owner to age out.
          FileUtils.rm_rf(dir)
          raise
        end

        true
      rescue Errno::EEXIST => e
        Master::Ground::Swallow.log(e, context: "LoopOwner.claim")
        false
      end

      # Removes only this process's claim: an ensure-block release must not
      # delete the slot another loop took after this one's claim was lost.
      def release
        return unless Dir.exist?(dir)

        current = read_claim
        FileUtils.rm_rf(dir) if current && own?(current)
      end

      def active
        cleanup_stale!
        return unless File.exist?(info)

        JSON.parse(File.read(info))
      rescue StandardError
        { "loop" => "unknown" }
      end

      def cleanup_stale!
        return unless File.exist?(info)

        data = JSON.parse(File.read(info))
        pid_text = data["pid"].to_s
        raise ArgumentError, "invalid loop owner PID" unless pid_text.match?(/\A[1-9]\d*\z/)

        FileUtils.rm_rf(dir) if stale?(data, pid_text.to_i)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LoopOwner.cleanup_stale!", severity: :load_bearing)
        nil
      end

      def stale?(data, pid)
        host = data["host"].to_s
        return !process_alive?(pid) if host.empty? || host == Socket.gethostname

        # Corrupt timestamps must not become epoch zero: raising keeps the
        # foreign claim instead of releasing it on an unreadable field.
        Time.now.utc - Time.iso8601(data.fetch("at").to_s) > STALE_SECONDS
      end

      def own?(data)
        data["pid"].to_s == Process.pid.to_s &&
          [Socket.gethostname, ""].include?(data["host"].to_s)
      end

      # An unreadable claim proves no owner, so release leaves it for
      # cleanup_stale!, which logs why it cannot judge it.
      def read_claim
        JSON.parse(File.read(info))
      rescue JSON::ParserError, SystemCallError
        nil # scan: intentional
      end

      # ESRCH is the answer, not a failure: the owner has exited.
      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # A refused claim leaves the holder in place: releasing here would delete
      # the owner file of the loop that does hold the slot.
      def with_claim(name)
        return false unless claim(name)

        begin
          yield
        ensure
          release
        end
      end
    end
  end
end
