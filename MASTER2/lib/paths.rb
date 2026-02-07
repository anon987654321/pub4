# frozen_string_literal: true

module MASTER
  module Paths
    class << self
      def root
        MASTER.root
      end

      def lib
        File.join(root, "lib")
      end

      def data
        File.join(root, "data")
      end

      def var
        @var ||= begin
          path = File.join(root, "var")
          FileUtils.mkdir_p(path)
          path
        end
      end

      def tmp
        @tmp ||= begin
          path = File.join(var, "tmp")
          FileUtils.mkdir_p(path)
          path
        end
      end

      def config
        @config ||= begin
          path = File.join(var, "config")
          FileUtils.mkdir_p(path)
          path
        end
      end

      def cache
        @cache ||= begin
          path = File.join(var, "cache")
          FileUtils.mkdir_p(path)
          path
        end
      end

      def logs
        @logs ||= begin
          path = File.join(var, "logs")
          FileUtils.mkdir_p(path)
          path
        end
      end

      def sessions
        @sessions ||= begin
          path = File.join(var, "sessions")
          FileUtils.mkdir_p(path)
          path
        end
      end
    end
  end
end
