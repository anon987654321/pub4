# frozen_string_literal: true

require 'yaml'

module MASTER
  class Principle
    class << self
      def load_all
        dir = Paths.principles
        return [] unless Dir.exist?(dir)

        Dir[File.join(dir, '*.yml')].sort.map do |path|
          parse(path)
        end
      end

      def load(name)
        dir = Paths.principles
        path = Dir[File.join(dir, "*#{name}*.yml")].first
        return nil unless path && File.exist?(path)

        parse(path)
      end

      private

      def parse(path)
        data = YAML.safe_load(File.read(path), permitted_classes: [], symbolize_names: true)
        data[:filename] = File.basename(path)
        data
      end
    end
  end
end
