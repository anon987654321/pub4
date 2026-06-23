# frozen_string_literal: true

module Master
  module Ground
    class OperatorPlaybook
      PATH = File.join(Master::DATA, "operator_playbook.yml").freeze

      def self.load
        Master.load_yaml(PATH, default: { "lessons" => [] })
      end

      def self.lessons
        Array(load["lessons"])
      end

      def self.for_area(area)
        key = area.to_s
        lessons.select { |row| row["area"].to_s == key }
      end

      def self.find(id)
        lessons.find { |row| row["id"].to_s == id.to_s }
      end

      def self.startup_bullets(limit: 8)
        lessons.first(limit).map { |row| format_lesson(row) }
      end

      def self.format_lesson(row)
        id = row["id"].to_s
        signal = row["signal"].to_s
        action = row["action"].to_s
        "[#{id}] #{signal} → #{action}"
      end

      def self.render(area: nil)
        rows = area ? for_area(area) : lessons
        return "operator_playbook: empty\n" if rows.empty?

        header = "operator_playbook (#{rows.size} lesson#{rows.size == 1 ? '' : 's'})"
        body = rows.map { |row| format_lesson(row) }
        ([header, ""] + body).join("\n")
      end
    end
  end
end