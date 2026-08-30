# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Ground
    module Antigravity
      # Artifacts manages Antigravity markdown artifacts, alerts, carousels,
      # mermaid diagrams, and JSONL transcripts.
      class Artifacts
        attr_reader :artifact_dir, :log_dir

        def initialize(artifact_dir: nil, log_dir: nil)
          @artifact_dir = artifact_dir || File.expand_path("~/.gemini/antigravity-cli/brain/default")
          @log_dir = log_dir || File.join(@artifact_dir, ".system_generated", "logs")
        end

        def create_artifact(filename, content, summary: nil, user_facing: true)
          FileUtils.mkdir_p(@artifact_dir)
          target_path = File.join(@artifact_dir, filename)
          File.write(target_path, content.to_s)
          {
            path: target_path,
            summary:,
            user_facing: !!user_facing,
          }
        end

        def format_alert(type, text)
          valid_types = %w[NOTE TIP IMPORTANT WARNING CAUTION]
          alert_type = valid_types.include?(type.to_s.upcase) ? type.to_s.upcase : "NOTE"
          "> [!#{alert_type}]\n> #{text.to_s.gsub("\n", "\n> ")}"
        end

        def format_mermaid(diagram_code)
          "```mermaid\n#{diagram_code.to_s.strip}\n```"
        end

        def format_carousel(slides)
          joined = Array(slides).map(&:to_s).join("\n<!-- slide -->\n")
          "````carousel\n#{joined}\n````"
        end

        def append_transcript_step(step_data, compact: true)
          FileUtils.mkdir_p(@log_dir)
          file_name = compact ? "transcript.jsonl" : "transcript_full.jsonl"
          target_path = File.join(@log_dir, file_name)

          payload = step_data.is_a?(Hash) ? step_data : { content: step_data.to_s }
          payload["created_at"] ||= Time.now.utc.iso8601

          File.open(target_path, "a:UTF-8") do |f|
            f.puts(JSON.generate(payload))
          end
          target_path
        end
      end
    end
  end
end
