# frozen_string_literal: true

module Master
  module Io
    # Schema-versioned JSON ledgers under .master/ — the content board, the
    # ideas ledger — fail closed on read. A file a hand edit or an older
    # writer left behind must stop the reader with the file path, the schema
    # it declares and the schema this code reads: the alternative, seen in
    # Board#load before this module, was a blanket rescue to an empty board
    # and a save that overwrites the ledger with the emptiness.
    module Ledger
      class Error < StandardError; end
      class Malformed < Error; end
      class SchemaMismatch < Error; end

      module_function

      # Returns the parsed object, or nil when no file exists yet — a fresh
      # ledger is empty, not corrupt.
      def read(path, schema:)
        return nil unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        unless data.is_a?(Hash)
          raise Malformed, "ledger #{path} holds a #{data.class}, not an object"
        end

        found = data["schema"]
        unless found == schema
          raise SchemaMismatch,
                "ledger #{path} declares schema #{found.inspect}, this code reads schema #{schema.inspect}; " \
                "regenerate the ledger or move it aside"
        end

        data
      rescue JSON::ParserError => e
        raise Malformed, "ledger #{path} is not valid JSON: #{e.message.split("\n").first}"
      end
    end
  end
end
