# frozen_string_literal: true

module MASTER
  # Centralized path management - DRY principle for all file system paths
  # All paths flow through this module to ensure consistency
  module Paths
    class << self
      # Root directory of MASTER installation
      # @return [String] Absolute path to root
      def root
        MASTER.root
      end

      # Library directory
      # @return [String] Path to lib/
      def lib
        File.join(root, "lib")
      end

      # Data directory for static resources
      # @return [String] Path to data/
      def data
        File.join(root, "data")
      end

      # Variable data directory (runtime state)
      # @return [String] Path to var/
      def var
        @var ||= mkdir(File.join(root, "var"))
      end

      # Temporary files directory
      # @return [String] Path to var/tmp/
      def tmp
        @tmp ||= mkdir(File.join(var, "tmp"))
      end

      # Configuration directory
      # @return [String] Path to var/config/
      def config
        @config ||= mkdir(File.join(var, "config"))
      end

      # Cache directory
      # @return [String] Path to var/cache/
      def cache
        @cache ||= mkdir(File.join(var, "cache"))
      end

      # Logs directory
      # @return [String] Path to var/logs/
      def logs
        @logs ||= mkdir(File.join(var, "logs"))
      end

      # Sessions directory
      # @return [String] Path to var/sessions/
      def sessions
        @sessions ||= mkdir(File.join(var, "sessions"))
      end

      # Database file path (JSONL backend)
      # @return [String] Path to db directory
      def db
        @db ||= mkdir(File.join(var, "db"))
      end

      # Dmesg log file path (kernel-style logging)
      # @return [String] Path to dmesg.log
      def dmesg_log
        @dmesg_log ||= File.join(logs, "dmesg.log")
      end

      # Semantic cache directory for embeddings
      # @return [String] Path to semantic_cache/
      def semantic_cache
        @semantic_cache ||= mkdir(File.join(cache, "semantic"))
      end

      # Edge TTS output directory
      # @return [String] Path to edge_tts output
      def edge_tts_output
        @edge_tts_output ||= mkdir(File.join(var, "edge_tts"))
      end

      # DRY helpers for common path patterns

      # Get session file path by ID
      # @param id [String] Session identifier
      # @return [String] Full path to session file
      def session_file(id)
        safe_id = File.basename(id.to_s)
        File.join(sessions, "#{safe_id}.json")
      end

      # Get file path in var directory
      # @param name [String] Filename
      # @return [String] Full path to var file
      def var_file(name)
        File.join(var, name)
      end

      # Get file path in data directory
      # @param name [String] Filename
      # @return [String] Full path to data file
      def data_file(name)
        File.join(data, name)
      end

      private

      # Create directory if it doesn't exist
      # @param path [String] Directory path
      # @return [String] The path created
      def mkdir(path)
        FileUtils.mkdir_p(path)
        path
      end
    end
  end
end
