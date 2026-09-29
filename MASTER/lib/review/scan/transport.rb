# frozen_string_literal: true

require "etc"
require "timeout"

module Master
  module Review
    module Scan
      module Transport
        # 5s, not 30: git here is only ever rev-parse and diff --name-only over
        # a local repo, and a scan that waits half a minute on a wedged index
        # has already cost more than the answer is worth.
        GIT_TIMEOUT_SECONDS = 5
        SCAN_SINCE_EXT = /\.(rb|rake|gemspec|erb|yml|yaml|js|css|sh|zsh)\z/.freeze
        GC_EVERY_N_ITERATIONS = 5

        private

        def git_capture(*argv)
          Timeout.timeout(GIT_TIMEOUT_SECONDS) { Master::Io::Exec.capture3(*argv) }
        rescue Timeout::Error
          ["", "git command timed out after #{GIT_TIMEOUT_SECONDS}s", failure_status]
        end

        def failure_status
          Struct.new(:success?).new(false)
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
            next unless File.exist?(path) && File.extname(path).match?(SCAN_SINCE_EXT)
            next unless under_path?(path, scan_root) || under_path?(path, master_lib)
            next if self.class.skip_path?(path, root: repo_root)

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

        def parallel_map(items)
          Master::Runtime::Compute.map(items, backend: :thread) do |item, index|
            maybe_gc(index)
            yield(item, index)
          rescue StandardError => e
            @bus&.publish("scanner:thread_error", path: item, index:, error: e.message)
            [item, Result.err(e.message, category: :infrastructure)]
          end
        end

        def maybe_gc(index)
          GC.start if index.positive? && (index % GC_EVERY_N_ITERATIONS).zero?
        end
      end
    end
  end
end
