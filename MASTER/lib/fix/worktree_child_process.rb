# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"
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
        GATE_BASELINE_STATE = "gate_baseline.json"
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

        # The baseline is read-only proof of the starting revision. Keep its
        # fingerprinted cache between disposable worktrees so an identical base
        # does not repeat the entire scan-only gate before every real repair.
        def carry_gate_baseline(worktree)
          source_dir = File.join(@repo_root, "MASTER", ".master")
          source = File.join(source_dir, GATE_BASELINE_STATE)
          return false unless safe_gate_baseline_path?(@repo_root, source_dir, source) && File.file?(source)

          destination_dir = File.join(worktree, "MASTER", ".master")
          destination = File.join(destination_dir, GATE_BASELINE_STATE)
          return false unless safe_gate_baseline_path?(worktree, destination_dir, destination)

          FileUtils.mkdir_p(destination_dir)
          FileUtils.cp(source, destination)
          true
        rescue SystemCallError => e
          announce("gate baseline cache not carried: #{e.class}")
          false
        end

        # Persist only the cache file, never the worker's entire ignored .master
        # directory. The key includes HEAD and the source-tree fingerprint, so a
        # cache from a changed or different base will simply be rejected.
        def persist_gate_baseline(worktree)
          source_dir = File.join(worktree, "MASTER", ".master")
          source = File.join(source_dir, GATE_BASELINE_STATE)
          return false unless safe_gate_baseline_path?(worktree, source_dir, source) && File.file?(source)

          destination_dir = File.join(@repo_root, "MASTER", ".master")
          destination = File.join(destination_dir, GATE_BASELINE_STATE)
          return false unless safe_gate_baseline_path?(@repo_root, destination_dir, destination)

          bytes = File.binread(source)
          FileUtils.mkdir_p(destination_dir)
          Tempfile.create(["gate-baseline", ".json"], destination_dir) do |file|
            file.binmode
            file.write(bytes)
            file.flush
            file.fsync
            File.rename(file.path, destination)
          end
          true
        rescue StandardError => e
          announce("gate baseline cache not persisted: #{e.class}")
          false
        end

        def safe_gate_baseline_path?(root, directory, path)
          base = File.expand_path(root)
          expanded = File.expand_path(path)
          return false if File.symlink?(directory) || File.symlink?(path)
          return false unless expanded.start_with?("#{base}#{File::SEPARATOR}")

          true
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
        ensure
          persist_gate_baseline(worktree) if worktree
        end

        def run_proof(worktree, proof_trees:)
          command = File.join(worktree, "MASTER", "bin", "operator")
          args = ["gate", "--fix-proof"]
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
