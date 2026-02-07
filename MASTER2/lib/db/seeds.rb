# frozen_string_literal: true

require "yaml"

module MASTER
  module DB
    module Seeds
      def self.run(db)
        seed_axioms(db)
        seed_council(db)
      end

      def self.seed_axioms(db)
        path = "#{MASTER.root}/data/axioms.yml"
        return unless File.exist?(path)

        axioms = YAML.safe_load_file(path)
        return unless axioms.is_a?(Array)

        axioms.each do |a|
          db.execute(
            "INSERT OR REPLACE INTO axioms (id, category, protection, title, statement, source) VALUES (?, ?, ?, ?, ?, ?)",
            [a["id"], a["category"], a["protection"], a["title"], a["statement"], a["source"]]
          )
        end
      end

      def self.seed_council(db)
        path = "#{MASTER.root}/data/council.yml"
        return unless File.exist?(path)

        data = YAML.safe_load_file(path)
        personas = data.select { |item| item.is_a?(Hash) && item["slug"] }

        personas.each do |p|
          db.execute(
            "INSERT OR REPLACE INTO council (slug, name, weight, temperature, veto, directive) VALUES (?, ?, ?, ?, ?, ?)",
            [p["slug"], p["name"], p["weight"], p["temperature"], p["veto"] ? 1 : 0, p["directive"]]
          )
        end

        # Store council params in config
        params = data.find { |item| item.is_a?(Hash) && !item["slug"] }
        return unless params

        params.each do |key, value|
          next if key == "veto_precedence"
          db.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["council_#{key}", value.to_s])
        end
      end
    end
  end
end
