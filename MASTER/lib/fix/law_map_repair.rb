# frozen_string_literal: true

require "json"
require "set"

module Master
  module Fix
    module LawMapRepair
      MIN_REGISTRY_SIZE = 100

      module_function

      def dangling_law_ids(root:)
        registered = Master::Review::Scan::LawTree.ids.map(&:upcase).to_set
        return [] if registered.size < MIN_REGISTRY_SIZE

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
        require File.join(Master::ROOT, "law", "definition")
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        ::Law.definitions.keys.map { |id| id.to_s.upcase }.to_set
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LawMapRepair.executable_law_ids", severity: :load_bearing)
        raise "law-map Law registry unreadable: #{e.class}: #{e.message}"
      end

      FLOW_WIDTH = 120

      # A row is JSON after its key, wrapped between fields and array items so no line passes
      # FLOW_WIDTH. Continuation lines sit six columns in; the last ends with the closing brace.
      def flow_row(name, row, width: FLOW_WIDTH)
        lines = ["    #{name}: {"]

        flow_tokens(row).each do |token|
          joined = join_token(lines.last, token)
          joined.size > width ? lines << "      #{token}" : lines[-1] = joined
        end
        "#{lines.join("\n")}\n"
      end

      def join_token(line, token)
        tight = line.end_with?("{", "[") || token.start_with?("]")
        tight ? "#{line}#{token}" : "#{line} #{token}"
      end

      def flow_tokens(row)
        last = row.size - 1
        tokens = row.each_with_index.flat_map do |(key, value), index|
          field_tokens(key, value, tail: index == last ? "" : ",")
        end
        tokens[-1] += "}"
        tokens
      end

      def field_tokens(key, value, tail:)
        label = JSON.generate(key)
        return ["#{label}: #{JSON.generate(value)}#{tail}"] unless value.is_a?(Array) && value.size > 1

        items = value.map { |item| "#{JSON.generate(item)}," }
        items[-1] = items.last.chomp(",")
        ["#{label}: [", *items, "]#{tail}"]
      end

      def flow_row_span(lines, index)
        stop = (index...lines.size).find { |i| lines[i].end_with?("}\n") }
        index..stop if stop
      end

      def remove_from_flow_row(lines, index, dangling:)
        law_id, reference = dangling
        return unless lines[index].start_with?("    #{law_id}: {")

        span = flow_row_span(lines, index) or return
        row = JSON.parse(lines[span].join.sub(/\A    #{Regexp.escape(law_id)}: /, ""))
        return unless row["law_ids"]&.delete(reference)

        [span, flow_row(law_id, row)]
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

          span, rewritten = remove_from_flow_row(lines, index, dangling: [law_id, reference])
          if span
            lines[span] = [rewritten]
            return lines.join
          end

          if (match = line.match(/\A    ([^:\s][^:]*)\s*:\s*\n\z/))
            current = match[1]
            in_law_ids = false
            next
          end

          if current == law_id && line.match?(/\A      law_ids:\s*\n\z/)
            in_law_ids = true
            next
          end

          if current == law_id && in_law_ids && line.match?(/\A {6,8}- #{Regexp.escape(reference)}\s*\n\z/)
            target = index
            break
          end

          in_law_ids = false if line.match?(/\A      [^\s-]/)
        end

        return text unless target

        lines.delete_at(target)
        lines.join
      end
    end
  end
end
