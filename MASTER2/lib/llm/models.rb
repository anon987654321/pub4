# frozen_string_literal: true

require "yaml"

module LLM
  module Models
    DATA_FILE_NAME = "models.yml"

    class LoadError < StandardError; end

    class RecordWrapper
      extend Forwardable

      def initialize(record)
        @record = record
      end

      attr_reader :record

      def_delegators :record, :id, :name, :kind, :enabled?
      def_delegators :provider, :key, :display_name

      delegate :key, :display_name, to: :provider

      private

      def provider
        record.provider
      end
    end

    class ModelStore
      def all_records
        Model.includes(:provider).order(:name)
      end

      def enabled_records
        all_records.where(enabled: true)
      end
    end

    class Catalog
      def initialize(store: ModelStore.new, paths: Paths)
        @store = store
        @paths = paths
      end

      def all(enabled_only: true)
        scope = enabled_only ? store.enabled_records : store.all_records
        scope.map { |record| RecordWrapper.new(record) }
      end

      def chat_models(enabled_only: true)
        filter_by_kind("chat", enabled_only: enabled_only)
      end

      def embedding_models(enabled_only: true)
        filter_by_kind("embedding", enabled_only: enabled_only)
      end

      def find(name, enabled_only: true)
        return nil unless name

        records = all(enabled_only: enabled_only)
        records.find { |wrapper| wrapper.name == name }
      end

      def metadata
        @metadata ||= load_metadata
      end

      def reload!
        @metadata = nil
        self
      end

      private

      attr_reader :store, :paths

      def filter_by_kind(kind, enabled_only:)
        models = all(enabled_only: enabled_only)
        models.select { |wrapper| wrapper.kind == kind }
      end

      def load_metadata
        file_path = paths.data_file(DATA_FILE_NAME)
        yaml = File.read(file_path)
        parsed = YAML.safe_load(yaml, permitted_classes: [], aliases: false)

        parsed.fetch("models", [])
      rescue Errno::ENOENT, Psych::SyntaxError => e
        raise LoadError, "Failed to load models metadata from #{file_path}: #{e.message}"
      end
    end

    module RubyLLMAdapter
      module_function

      def chat_model_names(ruby_llm: RubyLLM)
        models = ruby_llm.models
        chat_models = models.chat_models
        chat_models.map(&:name)
      end
    end
  end
end