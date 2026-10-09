# frozen_string_literal: true

require "yaml"

module Master
  module Convergence
    module Wishlist
      ROOT = Master::ROOT
      STATES = Master::Convergence::STATES

      module_function

      def config(root: ROOT)
        YAML.safe_load_file(File.join(root, "convergence.yml"), aliases: false) || {}
      end

      def items(root: ROOT)
        Array(config(root:).fetch("workstreams", [])).map { |item| normalize(item, root:) }
      end

      def find(query, root: ROOT)
        q = query.to_s.downcase.strip
        return if q.empty?

        items(root:).find { |item| "#{item[:id]} #{item[:title]}".downcase.include?(q) }
      end

      def summary(root: ROOT)
        rows = items(root:)
        counts = rows.group_by { |row| row[:state] }.transform_values(&:size)
        [
          "wishlist: #{rows.size} workstreams",
          STATES.map { |state| "#{state}=#{counts.fetch(state.to_s, 0)}" }.join(" "),
        ].join("\n")
      end

      def render(query = "", root: ROOT)
        return [summary(root:), *items(root:).map { |item| row(item) }].join("\n") if query.to_s.empty?

        item = find(query, root:)
        return "wishlist: no match for #{query.inspect}" unless item

        [
          "wishlist: #{item[:id]}",
          "state: #{item[:state]}",
          "title: #{item[:title]}",
          "implementation: #{item[:implementation]}",
          "implementation_present: #{item[:implementation_present]}",
          "proof: #{item[:proof]}",
        ].join("\n")
      end

      def normalize(item, root:)
        implementation = item.fetch("implementation")
        {
          id: item.fetch("id"),
          title: item.fetch("title"),
          state: STATES.include?(item.fetch("state").to_sym) ? item.fetch("state").to_s : "missing",
          implementation:,
          proof: item.fetch("proof").to_s,
          implementation_present: path_present?(root, implementation),
        }
      end

      def row(item)
        format("%-28s %-11s %s", item[:id], item[:state], item[:title])
      end

      def path_present?(_root, implementation)
        return true if %w[RAILS OPENBSD STUDIO].include?(implementation)

        path = File.expand_path(implementation, Master::REPO_ROOT)
        File.exist?(path)
      end
    end
  end
end
