# frozen_string_literal: true

require "set"

module Master
  module Fix
    module LawMapRepair
      MIN_REGISTRY_SIZE = 100

      module_function

      def dangling_law_ids(root:)
        Master::Review::Scan::LawDSL
        registry = Master::Review::Scan::Law.registry
        return [] if registry.size < MIN_REGISTRY_SIZE

        registered = registry.filter_map do |klass|
          Master::Review::Scan::LawFactory.registry_id(klass, root:)&.upcase
        end.to_set
        registered |= executable_law_ids

        map = Master::Ground::Map::LawMap.load(root:)
        map.laws.each_with_object([]) do |(id, entry), acc|
          entry.law_ids.each do |law_id|
            acc << [id, law_id] unless registered.include?(law_id.to_s.upcase)
          end
        end
      end

      def fix!(root:)
        path = File.join(root, "data", "laws.yml")
        return [] unless File.file?(path)

        dangling = dangling_law_ids(root:)
        return [] if dangling.empty?

        content = File.read(path, encoding: "UTF-8")
        dangling.each { |law_id, reference| content = remove_law_id(content, law_id, reference) }
        File.write(path, content)
        dangling
      end

      def executable_law_ids
        require File.join(Master::ROOT, "law", "law")
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        ::Law.definitions.keys.map { |id| id.to_s.upcase }.to_set
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LawMapRepair.executable_law_ids", severity: :load_bearing)
        raise "law-map Law registry unreadable: #{e.class}: #{e.message}"
      end

      def remove_law_id(text, law_id, reference)
        lines = text.lines
        in_law_map = false
        in_laws = false
        current = nil
        in_law_ids = false
        target = nil

        lines.each_with_index do |line, index|
          in_law_map = true if line == "law_map:\n"
          next unless in_law_map

          in_laws = true if line == "  laws:\n"
          next unless in_laws

          if (match = line.match(/\A    ([^:\s][^:]*)\s*:\s*\n\z/))
            current = match[1]
            in_law_ids = false
            next
          end

          if current == law_id && line.match?(/\A      law_ids:\s*\n\z/)
            in_law_ids = true
            next
          end

          if current == law_id && in_law_ids && line.match?(/\A        - #{Regexp.escape(reference)}\s*\n\z/)
            target = index
            break
          end

          in_law_ids = false if line.match?(/\A      \S/) && !line.match?(/\A      law_ids:/)
        end

        return text unless target

        lines.delete_at(target)
        lines.join
      end
    end
  end
end
