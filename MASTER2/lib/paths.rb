# frozen_string_literal: true

require "fileutils"

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

      def db
        @db ||= mkdir(File.join(var, "db"))
      end

      def dmesg_log
        @dmesg_log ||= File.join(logs, "dmesg.log")
      end

      def semantic_cache
        @semantic_cache ||= mkdir(File.join(cache, "semantic"))
      end

      def edge_tts_output
        @edge_tts_output ||= mkdir(File.join(var, "edge_tts"))
      end

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

      def data_path(name)
        base = data
        path = File.join(base, "#{name}.yml")
        return path if File.exist?(path)

        alt = File.join(base, name)
        return alt if File.exist?(alt)

        nil
      end

      def load_yaml(name)
        path = data_path(name)
        return nil unless path
        YAML.safe_load_file(path, symbolize_names: true)
      rescue StandardError
        nil
      end

      private

      def mkdir(path)
        FileUtils.mkdir_p(path)
        path
      end
    end
  end
end
