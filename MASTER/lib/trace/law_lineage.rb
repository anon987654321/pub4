# frozen_string_literal: true

require "pathname"

module Master
  module Trace
    # Joins existing constitutional sources. This class is a derived reader,
    # not another ownership, rule, architecture, or design registry.
    class LawLineage
      Node = Data.define(
        :path, :boundary, :entry, :depends_on, :check, :ownership, :laws
      )
      Law = Data.define(:id, :order, :statement)

      def initialize(root: Master::ROOT)
        @root = File.expand_path(root)
      end

      def explain(path)
        rel = relative_path(path)
        repo = repository_root
        absolute = File.join(repo, rel)
        boundary = Master::Phoenix.boundary_for(absolute, root: @root)
        ownership = ownership_for(absolute)
        row = Master::Phoenix.boundaries(root: @root).find { |item| item.name == boundary }
        return unless boundary || ownership || File.exist?(absolute)

        Node.new(
          rel,
          boundary,
          row&.entry,
          row&.depends_on || [],
          ownership&.fetch("check", nil) || row&.check,
          ownership,
          constitutional_laws,
        ).then { |node| render(node) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LawLineage.explain", severity: :cosmetic)
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

      # PATH_OWNERSHIP.yml keys are relative to MASTER (../RAILS/ for a
      # sibling tree), not to the checkout the lineage path is printed against.
      def ownership_for(absolute)
        map_path = File.join(@root, "PATH_OWNERSHIP.yml")
        return unless File.file?(map_path)

        rel = Pathname.new(absolute).relative_path_from(Pathname.new(@root)).to_s
        owned = (Master.load_yaml(map_path) || {}).fetch("ownership", {})
        owned
          .select { |key, _| covers?(key.to_s, rel) }
          .max_by { |key, _| key.to_s.length }
          &.last
      end

      def covers?(key, rel)
        return true if key == rel
        return true if key.end_with?("/") && "#{rel}/".start_with?(key)
        key.include?("*") && File.fnmatch?(key, rel)
      end

      # Law identity and file order come from the flat catalogue. Constitutional
      # precedence is the ordered node sequence declared by laws.yml.
      def constitutional_laws
        order = Master::Soul.invariant_order
        rows = Master.law_entries(root: @root)
        rows.each_with_index.map do |entry, index|
          node = constitutional_node(entry, rows)
          node_index = node && order.index(node)
          position = node_index ? node_index * 100_000 + index : order.length * 100_000 + index
          Law.new(entry.fetch("id").to_s, position, entry.fetch("statement").to_s)
        end
      end

      def constitutional_node(entry, rows, seen = {})
        id = entry.fetch("id").to_s
        return if seen[id]
        seen[id] = true
        return entry["node"].to_s if entry["node"]

        parent = entry["parent"]
        return unless parent

        parent_entry = rows.find { |row| row["id"].to_s.casecmp?(parent.to_s) }
        parent_entry && constitutional_node(parent_entry, rows, seen)
      end

      def render(node)
        lines = ["lineage: #{node.path}", "  status: RESOLVED"]
        lines << "  boundary: #{node.boundary}" if node.boundary
        lines << "  entry: #{node.entry}" if node.entry
        lines << "  depends_on: #{node.depends_on.join(", ")}" unless node.depends_on.empty?
        lines.concat(ownership_lines(node.ownership))
        lines << "  proof: #{node.check}" if node.check
        lines << "  constitution: data/laws.yml"
        lines << "  laws: #{node.laws.map(&:id).join(", ")}"
        lines << "  executable_law: law/"
        lines.join("\n")
      end

      def ownership_lines(ownership)
        return ["  ownership: UNDECLARED, add this path to PATH_OWNERSHIP.yml"] unless ownership

        ["  ownership: declared",
         ("  purpose: #{ownership["purpose"]}" if ownership["purpose"]),
         ("  risk: #{ownership["risk"]}" if ownership["risk"])].compact
      end

      def inconclusive(path, error)
        [
          "lineage: #{path}",
          "  status: INCONCLUSIVE",
          "  reason: #{error.class}: #{error.message}",
          "  constitution: data/laws.yml",
          "  executable_law: law/",
        ].join("\n")
      end
    end
  end
end
