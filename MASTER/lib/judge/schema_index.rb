# frozen_string_literal: true

module Master
  module Judge
    class SchemaIndex
      attr_reader :tables

      def initialize(root:)
        @root = root
        @tables = {}
        parse_schema
      end

      def indexed_columns(table_name)
        (@tables.dig(table_name, :indexes) || []).flat_map { |idx| idx[:columns] }
      end

      def columns(table_name)
        (@tables.dig(table_name, :columns) || [])
      end

      private

      def parse_schema
        path = File.join(@root, "db", "schema.rb")
        return unless File.exist?(path)
        File.readlines(path, chomp: true).each do |line|
          if line =~ /^\s*create_table\s+"([^"]+)"/
            table_name = Regexp.last_match(1)
            @tables[table_name] = { columns: [], indexes: [] }
          elsif table_name && line =~ /^\s*t\.\w+\s+"([^"]+)"/
            @tables[table_name][:columns] << Regexp.last_match(1)
          elsif line =~ /^\s*add_index\s+"([^"]+)",\s+\[(.+)\]/
            target = Regexp.last_match(1)
            cols = Regexp.last_match(2).scan(/"([^"]+)"/).flatten
            (@tables[target] ||= { columns: [], indexes: [] })[:indexes] << { columns: cols }
          end
        end
      end
    end
  end
end
