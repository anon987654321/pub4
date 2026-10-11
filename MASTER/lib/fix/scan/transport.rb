# frozen_string_literal: true

require "etc"
module Master
  module Fix
    module Scan
      module Transport
        # 5s, not 30: git here is only ever rev-parse and diff --name-only over
        # a local repo, and a scan that waits half a minute on a wedged index
        # has already cost more than the answer is worth.
        GIT_TIMEOUT_SECONDS = 5
        # Ruby's collector already adapts to allocation pressure. Forcing a
        # full collection every five files made large scans spend time collecting
        # rather than measuring. Keep manual collection opt-in for memory-heavy
        # diagnostics instead of making every normal scan pay for it.
        GC_EVERY_N_ITERATIONS = Integer(ENV.fetch("MASTER_SCAN_GC_EVERY", "0"))

        private

        def git_capture(*argv)
          Master::Io::Exec.capture3(*argv, timeout: GIT_TIMEOUT_SECONDS)
        end

        def changed_since(ref, repo_root)
          out, _, status = git_capture("git", "-C", repo_root, "diff", "--name-only", "#{ref}...HEAD")
          return Result.err("git diff failed", category: :validation) unless status.success?

          Result.ok(out.lines.map(&:strip).reject(&:empty?))
        end

        def scan_since_paths(changed, dir:, repo_root:)
          scan_root = File.expand_path(dir)
          master_lib = File.join(repo_root, "MASTER", "lib")
          paths = changed.filter_map do |rel|
            path = File.expand_path(rel, repo_root)
            next unless under_path?(path, scan_root) || under_path?(path, master_lib)
            next unless self.class.scan_candidate?(path, root: repo_root)

            path
          end
          paths.uniq
        end

        def under_path?(path, root)
          expanded_path = File.realpath(path)
          expanded_root = File.realpath(root)
          expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
        rescue StandardError
          expanded_path = File.expand_path(path)
          expanded_root = File.expand_path(root)
          expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
        end

        # Compute's own 30s deadline is for small jobs: it killed every scan of
        # a few thousand files at the 30s mark and reported a timeout instead of
        # findings. The scan's deadline is its own, in seconds.
        SCAN_TIMEOUT_SECONDS = Integer(ENV.fetch("MASTER_SCAN_TIMEOUT_S", "3600"))

        # One worker unless MASTER_SCAN_WORKERS says otherwise. The laws are pure
        # Ruby, so threads share one GVL and contend on it: RAILS (2,637 files)
        # took 71s on one worker and 158s on four.
        def scan_workers
          Integer(ENV.fetch("MASTER_SCAN_WORKERS", "1"))
        end

        def parallel_map(items)
          Master::Runtime::Compute.map(items, backend: :thread, workers: scan_workers, timeout: SCAN_TIMEOUT_SECONDS) do |item, index|
            maybe_gc(index)
            yield(item, index)
          rescue StandardError => e
            @bus&.publish("scanner:thread_error", path: item, index:, error: e.message)
            [item, Result.err(e.message, category: :infrastructure)]
          end
        end

        def maybe_gc(index)
          return if GC_EVERY_N_ITERATIONS <= 0
          return unless index.positive? && (index % GC_EVERY_N_ITERATIONS).zero?

          GC.start
        end
      end
    end
  end
end
