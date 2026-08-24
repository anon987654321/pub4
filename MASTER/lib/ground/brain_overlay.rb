# frozen_string_literal: true

module Master
  module Ground
    class BrainOverlay
      CORE_FILES = %w[
        standing_orders.rb
        policy/workflow.rb
        research_thresholds.rb
        tool/protocol.rb
        policy/subagent.rb
      ].freeze

      CONTEXTUAL_FILES = %w[
        policy_classifier.rb
        patch_verifier.rb
        done_checker.rb
        memory_search.rb
        context_compactor.rb
      ].freeze

      DEFAULT_MARKDOWN_DIRS = [
        File.join(Master::ROOT, "data", "claude"),
        File.join(Master::ROOT, ".master", "memory"),
      ].freeze

      attr_reader :root

      def initialize(root: Master::ROOT, markdown_dirs: DEFAULT_MARKDOWN_DIRS)
        @root = root
        @markdown_dirs = markdown_dirs
      end

      def core_brief
        lines = ["Brain overlay: Ruby policy is authoritative; markdown is legacy/contextual."]
        lines << Master::Ground::Tool::Protocol.brief if defined?(Master::Ground::Tool::Protocol)
        lines << Master::Ground::ResearchThresholds.brief if defined?(Master::Ground::ResearchThresholds)
        lines << Master::Ground::Policy::Workflow.brief if defined?(Master::Ground::Policy::Workflow)
        lines.compact.join("\n\n")
      end

      def contextual_index
        markdown_files.map do |path|
          rel = relative(path)
          title = File.basename(path)
          "#{rel} — #{title}"
        end
      end

      def load_context(name_or_pattern)
        pattern = name_or_pattern.to_s
        match = markdown_files.find do |path|
          relative(path).include?(pattern) || File.basename(path).include?(pattern)
        end
        return unless match

        File.read(match, encoding: "UTF-8")
      end

      def reloadable?
        true
      end

      private

      def markdown_files
        @markdown_dirs
          .flat_map { |dir| Dir.glob(File.join(dir, "**", "*.md")) }
          .select { |path| File.file?(path) }
      end

      def relative(path)
        path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
      end
    end
  end
end
