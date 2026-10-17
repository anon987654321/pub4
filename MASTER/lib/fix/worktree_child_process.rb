# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../trace/dmesg"

module Master
  module Fix
    class WorktreeSession
      # Runs the worker and the final proof as children inside the worktree,
      # streaming their output to the control-plane terminal.
      module ChildProcess
        # The small runtime state that is knowledge of which lanes answer: quota
        # deaths with their reset times, and the daily call counters. The worktree
        # checkout has no gitignored state, so without it the run learns each dead
        # lane again by failing on it. Copied, never linked, so the run cannot
        # write through to the operator files. Model choice is not carried.
        AVAILABILITY_STATE = %w[lane_quota.yml model_quota.json].freeze
        DEFAULT_CHILD_TIMEOUT_S = 14_400
        MAX_CHILD_TIMEOUT_S = 86_400
        TERMINATION_GRACE_S = 10

        private

        def carry_availability_state(worktree)
          from = File.join(@repo_root, "MASTER", ".master")
          to = File.join(worktree, "MASTER", ".master")
          carried = AVAILABILITY_STATE.select { |name| File.file?(File.join(from, name)) }
          return carried if carried.empty?

          FileUtils.mkdir_p(to)
          carried.each { |name| FileUtils.cp(File.join(from, name), File.join(to, name)) }
          carried
        end

        def run_child(worktree, command)
          env = ENV.to_h.merge(
            "MASTER_INTERNAL_CHILD" => "1",
            "MASTER_FIX_WORKTREE_CHILD" => "1",
            "MASTER_PROCESS_LOCK_FD" => nil,
            "MASTER_CONTROL_PLANE" => nil,
          )
          run_stream(
            env, File.join(worktree, "MASTER", "bin", "master"), command, chdir: worktree,
            timeout_s: configured_timeout_s("MASTER_FIX_WORKTREE_TIMEOUT_S"),
          )
        end

        def run_proof(worktree, proof_trees:)
          command = File.join(worktree, "MASTER", "bin", "operator")
          args = ["gate", "--scan-only"]
          trees = Array(proof_trees).map(&:to_s).select { |tree| TREES.include?(tree) }.uniq
          args << "--tree=#{trees.join(",")}" unless trees.empty? || trees.sort == TREES.sort
          run_stream(
            ENV.to_h.merge("MASTER_INTERNAL_CHILD" => "1"), command, *args, chdir: worktree,
            timeout_s: configured_timeout_s("MASTER_FIX_PROOF_TIMEOUT_S"),
          )
        end

        # Repair and proof may take a long time, but neither may hold the
        # operator forever. Stream concurrently and kill the whole child group
        # on timeout or interruption so grandchildren do not retain locks or pipes.
        def run_stream(env, command, *args, chdir:, timeout_s:, term_grace_s: TERMINATION_GRACE_S)
          lines = []
          status = nil
          timed_out = false
          cancelled = false

          Open3.popen2e(env, command, *args, chdir:, pgroup: true) do |stdin, io, wait_thr|
            stdin.close
            reader = Thread.new do
              Thread.current.report_on_exception = false
              begin
                io.each_line do |line|
                  clean = line.to_s.scrub.gsub(Master::Trace::Dmesg::ANSI, "").delete("\r")
                  next if clean.empty?

                  Master::Trace::Dmesg.forward(clean, io: @io)
                  lines << clean.chomp
                end
              rescue IOError, Errno::EBADF
                # Closing the pipe is part of bounded shutdown below.
              end
            end

            begin
              if wait_thr.join(timeout_s)
                status = wait_thr.value
              else
                timed_out = true
                terminate_child_group(wait_thr, grace_s: term_grace_s)
                status = wait_thr.value
              end
            rescue Interrupt
              cancelled = true
              terminate_child_group(wait_thr, grace_s: term_grace_s)
              status = wait_thr.value
            ensure
              unless reader.join(5)
                io.close rescue nil
                reader.kill
                reader.join
              end
            end
          end

          if timed_out
            terminal = "child timeout after #{timeout_s}s; process group terminated"
            lines << "worktree0: #{terminal}"
            Master::Trace::Dmesg.status("worktree0", terminal)
          elsif cancelled
            terminal = "child cancelled by operator; process group terminated"
            lines << "worktree0: #{terminal}"
            Master::Trace::Dmesg.status("worktree0", terminal)
          end

          [status&.success? && !timed_out && !cancelled, lines]
        end

        def configured_timeout_s(key)
          seconds = Integer(ENV.fetch(key, DEFAULT_CHILD_TIMEOUT_S.to_s), 10)
          return seconds if seconds.between?(1, MAX_CHILD_TIMEOUT_S)

          raise ArgumentError
        rescue ArgumentError
          raise ArgumentError, "#{key} must be an integer between 1 and #{MAX_CHILD_TIMEOUT_S} seconds"
        end

        def terminate_child_group(wait_thr, grace_s:)
          pid = wait_thr.pid
          begin
            Process.kill("TERM", -pid)
          rescue Errno::ESRCH
            return wait_thr.join(grace_s) unless wait_thr.alive?
          end

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + grace_s
          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            wait_thr.join(0.05)
            break unless process_group_alive?(pid)
          end

          if process_group_alive?(pid)
            begin
              Process.kill("KILL", -pid)
            rescue Errno::ESRCH
              nil
            end
          end
          raise "child process #{pid} could not be reaped after group termination" unless wait_thr.join(grace_s)
        end

        def process_group_alive?(pid)
          Process.kill(0, -pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end
      end
    end
  end
end
