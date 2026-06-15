# frozen_string_literal: true

module Master
  module Judge
    class FileRecord < Data.define(
      :path, :full_path, :basename, :dirname, :ext,
      :bytes, :lines, :symbol_count, :tokens, :digest, :signature, :inbound_refs
    )
      def self.from_hash(hash)
        return nil unless hash.is_a?(Hash)

        new(**hash.slice(*members).transform_keys(&:to_sym))
      end

      def to_h
        members.to_h { |m| [m, public_send(m)] }
      end

      def [](key)
        public_send(key) if members.include?(key)
      end
    end
  end
end