# frozen_string_literal: true

require "open3"

module Master
  module Loop
    class FixLoop
      # Scan-only helpers extracted from FixLoop (O103).
      class Scanner
        SKIP_DIRS = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze

        def initialize(scanner:, root:, bus: nil)
          @scanner = scanner
          @root = root
          @bus = bus
        end

        def scan_violations(files)
          files.flat_map do |path|
            next [] unless File.exist?(path)
            result = @scanner.scan(path)
            findings = Result.wrap(result).value_or([])
            stream_scan_progress(path, findings.size)
            findings.map { |v| v.to_h.merge(file: path.delete_prefix("#{@root}/")) }
          end
        end

        def ground_truth_violations(files)
          files.each { |path| File.read(path, encoding: "UTF-8") if File.file?(path) }
          scan_violations(files)
        end

        def collect_files(target)
          Dir.glob(File.join(target, "**", "*"))
             .select { |f| File.file?(f) && !binary?(f) }
             .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
        end

        def collect_changed_files(target, git:)
          changed = changed_since_last_commit(target, git:)
          return collect_files(target) if changed.empty?
          changed
        rescue StandardError => e
          @bus&.publish("fix_loop:incremental_fallback", error: e.message)
          collect_files(target)
        end

        private

        def binary?(path)
          sample = File.binread(path, 8192)
          sample.include?("\x00")
        rescue StandardError
          true
        end

        def stream_scan_progress(path, count)
          rel = path.delete_prefix("#{@root}/").delete_prefix("/")
          @bus&.publish("fix_loop:scan_progress", path: rel, violations: count)
          return unless count.positive?
          $stdout.puts "fix: #{rel} #{count} violation(s)"
          $stdout.flush
        end

        def changed_since_last_commit(target, git:)
          out, _, status = Open3.capture3("git", "-C", @root, "diff", "--name-only", "HEAD")
          return [] unless status.success?
          out.lines.map(&:strip).reject(&:empty?)
             .map { |rel| File.join(@root, rel) }
             .select { |f| File.exist?(f) && f.start_with?(target) }
             .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
             .sort
        end
      end
    end
  end
end