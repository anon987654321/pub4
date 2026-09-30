# frozen_string_literal: true

require "yaml"

module Master
  module Trace
    # Derives constitutional lineage for a path without introducing another
    # ownership or rule registry. It joins the sources that already own meaning:
    # data/rules.yml, Phoenix architecture, and PATH_OWNERSHIP.yml where present.
    class RuleLineage
      Node = Data.define(:path, :boundary, :entry, :check, :purpose, :risk)

      def initialize(root: Master::ROOT)
        @root = File.expand_path(root)
      end

      def explain(path)
        rel = relative_path(path)
        boundary = Master::Phoenix.boundary_for(File.join(@root, rel), root: @root)
        ownership = ownership_for(rel)
        return if boundary.nil? && ownership.nil?

        row = Master::Phoenix.boundaries(root: @root).find { |item| item.name == boundary }

        Node.new(
          rel,
          boundary,
          row&.entry,
          ownership&.fetch("check", nil) || row&.check,
          ownership&.fetch("purpose", nil),
          ownership&.fetch("risk", nil)
        ).then { |node| render(node) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLineage.explain", severity: :cosmetic)
        nil
      end

      private

      def relative_path(path)
        absolute = File.expand_path(path.to_s, @root)
        repo = Master::Phoenix.send(:repo_root, @root)
        absolute.delete_prefix("#{repo}/")
      end

      def ownership_for(rel)
        map_path = File.join(@root, "PATH_OWNERSHIP.yml")
        return unless File.file?(map_path)

        owned = (Master.load_yaml(map_path) || {}).fetch("ownership", {})
        hit = owned.find { |key, _| covers?(key.to_s, rel) }
        hit&.last if hit
      end

      def covers?(key, rel)
        return true if key == rel
        return true if key.end_with?("/") && rel.start_with?(key)
        key.include?("*") && File.fnmatch?(key, rel)
      end

      def render(node)
        lines = ["lineage: #{node.path}"]
        lines << "  boundary: #{node.boundary}" if node.boundary
        lines << "  entry: #{node.entry}" if node.entry
        lines << "  purpose: #{node.purpose}" if node.purpose
        lines << "  risk: #{node.risk}" if node.risk
        lines << "  proof: #{node.check}" if node.check
        lines << "  constitution: data/rules.yml"
        lines << "  executable_law: law/"
        lines.join("\n")
      end
    end
  end
end
