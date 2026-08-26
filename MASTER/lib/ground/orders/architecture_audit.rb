# frozen_string_literal: true

module Master
  module Ground
    module Orders
      # Weekly review of data/* shape misfit. Walks every yaml under data/, flags
      # files that grew past LINE_LIMIT (split candidate), files with overlapping
      # top-level keys (merge candidate), and emits suggestions to the bus.
      class ArchitectureAudit < Base
        LINE_LIMIT = 200

        def call
          data_dir = File.join(root, "data")
          bloated = bloated_files(data_dir)
          overlaps = overlapping_keys(data_dir)
          bus&.publish("architecture_audit:bloated", files: bloated)
          bus&.publish("architecture_audit:overlap", pairs: overlaps)
          Result.ok(bloated:, overlaps:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def bloated_files(dir)
          Dir.glob(File.join(dir, "*.yml")).filter_map do |f|
            lines = File.foreach(f).count
            [File.basename(f), lines] if lines > LINE_LIMIT
          end.sort_by { |_, n| -n }
        end

        def overlapping_keys(dir)
          files = Dir.glob(File.join(dir, "*.yml"))
          keys = files.each_with_object({}) do |f, h|
            document = begin
              Master.load_yaml(f)
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "architecture_audit.overlapping_keys", path: f)
              nil
            end
            h[File.basename(f)] = document.is_a?(Hash) ? document.keys : []
          end
          pairs = []
          keys.to_a.combination(2) do |(a, ka), (b, kb)|
            shared = ka & kb
            pairs << [a, b, shared] if shared.any?
          end
          pairs
        end
      end
    end
  end
end
