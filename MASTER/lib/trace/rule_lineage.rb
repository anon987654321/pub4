# frozen_string_literal: true

module Master
  module Trace
    # Joins existing constitutional sources. This class is a derived reader,
    # not another ownership, rule, architecture, or design registry.
    class RuleLineage
      Node = Data.define(
        :path, :boundary, :entry, :depends_on, :check, :ownership, :laws
      )
      Law = Data.define(:id, :priority, :principle)

      def initialize(root: Master::ROOT)
        @root = File.expand_path(root)
      end

      def explain(path)
        rel = relative_path(path)
        repo = repository_root
        absolute = File.join(repo, rel)
        boundary = Master::Phoenix.boundary_for(absolute, root: @root)
        ownership = ownership_for(rel)
        row = Master::Phoenix.boundaries(root: @root).find { |item| item.name == boundary }
        return unless boundary || ownership || File.exist?(absolute)

        Node.new(
          rel,
          boundary,
          row&.entry,
          row&.depends_on || [],
          ownership&.fetch("check", nil) || row&.check,
          ownership,
          constitutional_laws
        ).then { |node| render(node) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "RuleLineage.explain", severity: :cosmetic)
        inconclusive(path, e)
      end

      private

      def repository_root
        Master::Phoenix.repository_root(root: @root)
      end

      def relative_path(path)
        absolute = File.expand_path(path.to_s, @root)
        repo = repository_root
        prefix = "#{repo}#{File::SEPARATOR}"
        absolute.start_with?(prefix) ? absolute.delete_prefix(prefix) : path.to_s
      end

      def ownership_for(rel)
        map_path = File.join(@root, "PATH_OWNERSHIP.yml")
        return unless File.file?(map_path)

        owned = (Master.load_yaml(map_path) || {}).fetch("ownership", {})
        owned
          .select { |key, _| covers?(key.to_s, rel) }
          .max_by { |key, _| key.to_s.length }
          &.last
      end

      def covers?(key, rel)
        return true if key == rel
        return true if key.end_with?("/") && rel.start_with?(key)
        key.include?("*") && File.fnmatch?(key, rel)
      end

      def constitutional_laws
        laws = (Master.load_rules(root: @root) || {})["laws"] || {}
        laws.map do |id, value|
          Law.new(id.to_s, value.fetch("priority"), value.fetch("principle").to_s)
        end.sort_by(&:priority)
      end

      def render(node)
        lines = ["lineage: #{node.path}", "  status: RESOLVED"]
        lines << "  boundary: #{node.boundary}" if node.boundary
        lines << "  entry: #{node.entry}" if node.entry
        lines << "  depends_on: #{node.depends_on.join(", ")}" unless node.depends_on.empty?
        if node.ownership
          lines << "  ownership: declared"
          lines << "  purpose: #{node.ownership["purpose"]}" if node.ownership["purpose"]
          lines << "  risk: #{node.ownership["risk"]}" if node.ownership["risk"]
          lines << "  proof: #{node.check}" if node.check
        else
          lines << "  ownership: UNDECLARED"
          lines << "  proof: add this path to PATH_OWNERSHIP.yml"
        end
        lines << "  constitution: data/laws.yml"
        lines << "  laws: #{node.laws.map(&:id).join(", ")}"
        lines << "  executable_law: law/"
        lines.join("\n")
      end

      def inconclusive(path, error)
        [
          "lineage: #{path}",
          "  status: INCONCLUSIVE",
          "  reason: #{error.class}: #{error.message}",
          "  constitution: data/laws.yml",
          "  executable_law: law/"
        ].join("\n")
      end
    end
  end
end
