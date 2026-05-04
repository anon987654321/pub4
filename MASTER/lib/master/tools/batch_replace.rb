# frozen_string_literal: true

module Master
  module Tools
    # BatchReplace — apply multiple search-and-replace operations in one pass.
    class BatchReplace
      include AtomicWrite
      TIER        = :guarded
      NAME        = "replace".freeze
      DESCRIPTION = "Find and replace text across all files in a directory.".freeze

      SAFE_EXTENSIONS = %w[.rb .erb .yml .yaml .md .sh .js .css .html .json .txt].freeze

      SACRED_DENY = %w[SOUL.md CLAUDE.md CONVENTIONS.md README.md data/].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        perm = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return perm if perm.err?

        target = dir ? File.expand_path(dir, @root) : @root
        return Result.err("replace: path escapes root: #{dir}", category: :validation) unless target.start_with?(@root)
        return Result.err("replace: directory not found: #{target}", category: :validation) unless Dir.exist?(target)

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)

        changed = 0
        Dir.glob("#{target}/**/*").each do |path|
          next unless File.file?(path)
          next unless SAFE_EXTENSIONS.include?(File.extname(path))
          rel = path.delete_prefix("#{@root}/")
          next if SACRED_DENY.any? { |s| rel == s || rel.start_with?(s) }
          content = File.read(path, encoding: "UTF-8") rescue next
          next unless content.include?(old_str)
          write_atomic(path, content.gsub(old_str, new_str))
          changed += 1
        end

        if rename_files
          Dir.glob("#{target}/**/*")
             .select { |p| File.file?(p) && File.basename(p).include?(old_str) }
             .each do |path|
               rel = path.delete_prefix("#{@root}/")
               next if SACRED_DENY.any? { |s| rel == s || rel.start_with?(s) }
               new_path = File.join(File.dirname(path), File.basename(path).gsub(old_str, new_str))
               File.rename(path, new_path)
               changed += 1
             end
        end

        @bus&.publish("tool:after", tool: NAME)
        Result.ok("replaced in #{changed} file(s)")
      rescue StandardError => e
        Result.err("replace: #{e.message}", category: :unknown)
      end
    end
  end
end
