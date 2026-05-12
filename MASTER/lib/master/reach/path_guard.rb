# frozen_string_literal: true

module Master
  module Reach
    module PathGuard
      SACRED_PATHS = begin
        data = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
        Array(data.dig("absolute", "sacred_paths")).freeze
      rescue StandardError
        %w[data/ SOUL.md CLAUDE.md CONVENTIONS.md README.md .claude/].freeze
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)

        rel = full.delete_prefix(@root + "/")
        if sacred?(rel)
          return Result.err(
            "#{rel} is sacred-tier (constitutional). Amend via `soul propose`.",
            category: :validation
          )
        end

        Result.ok(full)
      end

      private

      def sacred?(rel_path)
        SACRED_PATHS.any? { |s| rel_path.start_with?(s) || rel_path == s.chomp("/") }
      end
    end
  end
end
