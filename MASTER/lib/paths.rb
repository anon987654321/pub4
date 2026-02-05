# frozen_string_literal: true

module MASTER
  # Centralized path management - DRY principle
  # One source of truth for all directory paths
  module Paths
    class << self
      def root
        @root ||= File.expand_path('..', __dir__)
      end

      def lib
        @lib ||= File.join(root, 'lib')
      end

      def principles
        @principles ||= File.join(lib, 'principles')
      end

      def personas
        @personas ||= File.join(lib, 'personas')
      end

      def var
        @var ||= File.join(root, 'var')
      end

      def data
        @data ||= File.join(var, 'data')
      end

      def screenshots
        @screenshots ||= File.join(var, 'screenshots')
      end

      def replicate
        @replicate ||= File.join(var, 'replicate')
      end

      def history
        @history ||= File.expand_path('~/.master_history')
      end

      # Ensure directory exists, return path
      def ensure(path)
        FileUtils.mkdir_p(path) unless Dir.exist?(path)
        path
      end
    end
  end
end
