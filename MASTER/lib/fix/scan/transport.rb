# frozen_string_literal: true

require "English"
require "etc"
require "json"

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
        FORK_MIN_ITEMS = 200

        # A forked worker: the files it took, its pid, and the pipe its findings come back on.
        ForkWorker = Data.define(:slice, :pid, :reader)

        # Forked workers, each scanning a share of the files. The laws are pure Ruby, so threads share one
        # GVL and a 5,400-file walk ran on one core whatever scan_workers said. MASTER_SCAN_PROCESSES (3 by
        # default) sets how many; a small walk, or 1, stays in this process. A worker's findings come
        # back as FindingCodec JSON, and a slice whose worker failed is scanned again here.
        def fork_map(items, &block)
          count = Integer(ENV.fetch("MASTER_SCAN_PROCESSES", "3"), exception: false) || 1
          return block.call(items) if count <= 1 || items.size < FORK_MIN_ITEMS || Gem.win_platform?

          workers = items.each_slice((items.size / count.to_f).ceil).map { |slice| fork_worker(slice, &block) }
          workers.flat_map { |worker| collect_worker(worker, &block) }
        end

        private

        def fork_worker(slice, &block)
          reader, writer = IO.pipe
          # exit! on both paths: a raise would run the parent's at_exit hooks in the child, and the
          # parent redoes the slice of a worker that failed.
          pid = fork do
            reader.close
            writer.write(JSON.generate(FindingCodec.encode(block.call(slice))))
            writer.close
            exit!(0)
          rescue StandardError
            exit!(1)
          end

          writer.close
          ForkWorker.new(slice:, pid:, reader:)
        end

        def collect_worker(worker, &block)
          text = worker.reader.read
          worker.reader.close
          Process.wait(worker.pid)
          return block.call(worker.slice) unless $CHILD_STATUS&.success? && !text.empty?

          FindingCodec.decode(JSON.parse(text))
        end

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

        # MASTER_SCAN_WORKERS, else scan.yml scan_workers. The lexical Laws are pure Ruby, so threads share
        # one GVL and contend on it (RAILS took 71s on one worker and 158s on four); the semantic Laws wait on
        # a model, and there threads overlap the waiting. Strict mode reads every file semantically, so the
        # data default favours the wait.
        def scan_workers
          Integer(ENV.fetch("MASTER_SCAN_WORKERS") { Master.config_section("scan_workers") || 1 })
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
