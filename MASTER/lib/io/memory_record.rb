# frozen_string_literal: true

require "fileutils"
require_relative "../ground/personal_workspace"
require_relative "../ground/redactor"
require_relative "atomic_write"

module Master
  module Io
    # MemoryRecord — writes durable context into data/project_context.yml and
    # seeds Master::Ground::Memory so semantic recall sees it immediately.
    class MemoryRecord
      include AtomicWrite

      NAME = "memory_record".freeze
      DESCRIPTION = "Write a durable project-context entry. " \
                    "Use for user facts, feedback, project context, or external references.".freeze
      CONTEXT_PATH = "project_context.yml".freeze
      TIER = :open

      def initialize(memory:, root: Dir.pwd, event_bus: nil)
        @memory = memory
        @root = root
        @bus = event_bus
      end

      def call(key:, description:, body:, type: "general")
        key = key.to_s.strip.downcase
        type = VALID_TYPES.include?(type.to_s) ? type.to_s : "general"
        return Result.err("memory_record: key must match #{KEY_RE.source}", category: :validation) unless KEY_RE.match?(key)

        subject = Fiber[:master_pair_subject].to_s
        if subject.strip.empty? && Fiber[:master_visitor] != true && defined?(Master::Device::Agent) &&
            Master::Device.android? && Master::Device::Agent.paired?(root: @root)
          subject = Master::Device::Agent.owner_subject(root: @root)
        end

        if subject.strip != ""
          unless Master::Ground::PersonalWorkspace.permission_granted?(root: @root, subject:)
            return Result.err(
              "memory_record: personal profile and memory are disabled; use /privacy grant personal_memory in the local paired session",
              category: :policy,
            )
          end

          path = Master::Ground::PersonalWorkspace.append_memory(root: @root, subject:, key:, body:, type:)
          @bus&.publish("memory:record", key:, type:, path: relative(path), paired: true)
          return Result.ok("memory_record: #{relative(path)}")
        end

        # project_context.yml is tracked and pushed: a web visitor fell through the paired
        # check above and wrote into it, and a model's body went to git with any secret in it.
        if Fiber[:master_visitor] == true
          return Result.err("memory_record: visitors cannot write the shared project context", category: :policy)
        end

        if type == "user"
          return Result.err(
            "memory_record: personal facts require a paired subject; refusing to write them to shared project_context.yml",
            category: :policy,
          )
        end

        path = persist_context(key:, description:, type:, body:)
        @memory&.remember("claude/#{key}", body.to_s.strip, type:)
        @bus&.publish("memory:record", key:, type:, path: relative(path))
        Result.ok("memory_record: #{relative(path)}")
      rescue Master::Ground::PersonalWorkspace::PermissionDenied => e
        Result.err("memory_record: #{e.message}", category: :policy)
      rescue StandardError => e
        Result.err("memory_record: #{e.message}", category: :unknown)
      end

      private

      def persist_context(key:, description:, type:, body:)
        path = File.join(@root, "data", CONTEXT_PATH)
        data = File.file?(path) ? Master.load_yaml(path) : { "meta" => { "source" => "memory_record" }, "entries" => [] }
        entries = Array(data["entries"]).reject { |row| row.is_a?(Hash) && row["key"].to_s == key }
        entries << {
          "key" => key,
          "name" => key.tr("_", " "),
          "description" => Master::Ground::Redactor.text(description.to_s.strip),
          "type" => type,
          "body" => Master::Ground::Redactor.text(body.to_s.strip),
        }
        data["entries"] = entries
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, data.to_yaml)
        path
      end

      def relative(path) = path.sub("#{@root}/", "")

      VALID_TYPES = %w[user feedback project reference general].freeze
      KEY_RE = /\A[a-z0-9][a-z0-9_]{1,60}\z/.freeze
    end
  end
end
