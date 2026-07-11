# frozen_string_literal: true

module Master
  module Ground
    class AgentMap
      PATH = File.join(Master::ROOT, "data", "agent_map.yml").freeze

      class << self
        def load
          Master.load_yaml(PATH, default: {}) || {}
        end

        def topic(name)
          load.dig("topics", name.to_s)
        end

        def patch_brief(relative_path)
          key = relative_path.to_s.delete_prefix("/")
          brief = load.dig("patch_briefs", key)
          return nil unless brief

          lines = ["patch brief: #{key}"]
          Array(brief["tests"]).each { |t| lines << "  test: #{t}" }
          lines << "  deploy: #{brief['deploy']}" if brief["deploy"]
          lines << "  post: #{brief['post']}" if brief["post"]
          lines << "  playbook: #{brief['playbook']}" if brief["playbook"]
          lines << "  note: #{brief['note']}" if brief["note"]
          lines.join("\n")
        end

        def format_topics
          topics = load["topics"] || {}
          return "(empty agent_map.yml)" if topics.empty?

          topics.map do |name, entry|
            files = Array(entry["files"]).join(", ")
            tests = Array(entry["tests"]).join(", ")
            [
              "#{name}:",
              "  files: #{files}",
              ("  tests: #{tests}" unless tests.empty?),
              ("  deploy: #{entry['deploy']}" if entry["deploy"]),
              ("  playbook: #{entry['playbook']}" if entry["playbook"]),
              ("  note: #{entry['note']}" if entry["note"]),
            ].compact.join("\n")
          end.join("\n\n")
        end
      end
    end
  end
end