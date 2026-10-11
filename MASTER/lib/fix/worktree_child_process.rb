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
          run_stream(env, File.join(worktree, "MASTER", "bin", "master"), command, chdir: worktree)
        end

        def run_proof(worktree, proof_trees:)
          command = File.join(worktree, "MASTER", "bin", "operator")
          args = ["gate", "--scan-only"]
          trees = Array(proof_trees).map(&:to_s).select { |tree| TREES.include?(tree) }.uniq
          args << "--tree=#{trees.join(",")}" unless trees.empty? || trees.sort == TREES.sort
          run_stream(ENV.to_h.merge("MASTER_INTERNAL_CHILD" => "1"), command, *args, chdir: worktree)
        end

        def run_stream(env, command, *args, chdir:)
          lines = []
          status = nil
          Open3.popen2e(env, command, *args, chdir:) do |stdin, io, wait_thr|
            stdin.close
            io.each_line do |line|
              clean = line.to_s.scrub.gsub(Master::Trace::Dmesg::ANSI, "").delete("\r")
              next if clean.empty?

              Master::Trace::Dmesg.forward(clean, io: @io)
              lines << clean.chomp
            end
            status = wait_thr.value
          end
          [status.success?, lines]
        end
      end
    end
  end
end
