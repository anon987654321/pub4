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
        @var ||= mkdir(File.join(root, "var"))
      end

      def tmp
        @tmp ||= mkdir(File.join(var, "tmp"))
      end

      def config
        @config ||= mkdir(File.join(var, "config"))
      end

      def cache
        @cache ||= mkdir(File.join(var, "cache"))
      end

      def logs
        @logs ||= mkdir(File.join(var, "logs"))
      end

      def sessions
        @sessions ||= mkdir(File.join(var, "sessions"))
      end

      # DRY helpers for common path patterns
      def session_file(id)
        safe_id = File.basename(id.to_s)
        File.join(sessions, "#{safe_id}.json")
      end

      def var_file(name)
        File.join(var, name)
      end

      def data_file(name)
        File.join(data, name)
      end

      private

      def mkdir(path)
        FileUtils.mkdir_p(path)
        path
      end
    end
  end
end
