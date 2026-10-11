# frozen_string_literal: true

require "open3"
require_relative "../trace/dmesg"

module Master
  module Fix
    class WorktreeSession
      # Runs the worker and the final proof as children inside the worktree,
      # streaming their output to the control-plane terminal.
      module ChildProcess
        private

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
