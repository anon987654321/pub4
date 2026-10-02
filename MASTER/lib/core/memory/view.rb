# frozen_string_literal: true

module Master::Core
  class Memory
    class View
      Permission = Data.define(:path, :mode)
      MODES = %i[read write].freeze

      def initialize
        @entries = []
        @locked = false
      end

      def unveil(paths, mode = :read)
        raise SecurityError, "memory view is locked" if @locked

        pairs = paths.is_a?(Hash) ? paths : { paths => mode }
        pairs.each do |path, permission|
          permission = permission.to_sym
          raise ArgumentError, "unknown memory permission: #{permission}" unless MODES.include?(permission)

          @entries << Permission.new(normalize(path), permission)
        end
        @entries.uniq!
        self
      end

      def lock!
        @locked = true
        freeze
      end

      def locked? = @locked

      def allowed?(path, mode = :read)
        candidate = normalize(path)
        requested = mode.to_sym
        @entries.any? do |entry|
          next false unless candidate == entry.path || candidate.start_with?("#{entry.path}/")
          entry.mode == :write || entry.mode == requested
        end
      end

      def require!(path, mode = :read)
        return true if allowed?(path, mode)
        raise SecurityError, "memory view refused: #{path}"
      end

      def paths = @entries.map(&:path).uniq.freeze

      private

      def normalize(path)
        value = path.to_s.sub(%r{A./}, "")
        value = File.expand_path(value, "/")
        value.sub(%r{A/}, "")
      end
    end
  end
end