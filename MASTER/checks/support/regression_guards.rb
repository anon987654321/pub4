# frozen_string_literal: true

require "json"
require "yaml"
require "date"

module Deploy
  # What keeps a defect the visual lane fixed from coming back. Each cleared group leaves a row in
  # geometry_surfaces.yml#regression_guards (the finding kind, its selector or stylesheet, its
  # surfaces); a later soft finding of that kind, on that selector, on one of those surfaces is no
  # longer soft: CheckResult reports it hard, "[guarded]", so the regression blocks.
  module RegressionGuards
    DATA = File.join(File.expand_path("..", __dir__), "data", "geometry_surfaces.yml")

    module_function

    def rows(path = DATA) = Array((YAML.safe_load_file(path) || {})["regression_guards"])

    def guarded?(message, rows: cached)
      rows.any? do |row|
        places = [row["selector"], row["file"]].compact
        message.include?("#{row["kind"]}:") && places.any? { |place| message.include?(place) } &&
          Array(row["surfaces"]).any? { |surface| message.include?(surface) }
      end
    end

    def cached = (@cached ||= File.file?(DATA) ? rows : [])

    def reset! = @cached = nil

    # Appended as text so the file's comments survive; the key is the file's last.
    def record(kind:, place:, surfaces:, path: DATA)
      row = { "kind" => kind, place.key?(:selector) ? "selector" : "file" => place.values.first,
              "surfaces" => surfaces.first(3), "since" => Date.today.iso8601 }
      return row if rows(path).any? { |kept| kept.except("since") == row.except("since") }

      File.open(path, "a") { |file| file.puts("  - #{row.to_json}") }
      reset!
      row
    end
  end
end
