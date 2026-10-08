# frozen_string_literal: true

module Master
  module CLI
    class Pipeline
      class Pass
        Result = Data.define(:target, :mode, :sections, :ok, :unit, :failed_stages, :totals) do
          def initialize(totals: {}, **fields) = super(totals:, **fields)

          def counts
            before, after = totals.values_at(:before, :after)
            return unless before

            after ? "#{before} findings, #{after} after the fix" : "#{before} findings"
          end

          SECTION_UNITS = {
            "mode" => "mode0",
            "stages" => "review0",
            "observe" => "obs0",
            "re-observe" => "obs1",
            "repair" => "fix0",
            "would repair" => "fix0",
            "changes" => "change0",
            "critique" => "crit0",
            "principle map" => "map0",
            "proof" => "proof0",
          }.freeze

          def render
            header = Master::Trace::Dmesg::Report.render(
              unit:, parent: "master0",
              text: "#{target}, #{mode}"
            )
            body = sections.filter_map do |title, section|
              next if title.to_s == "mode" && section.to_s.empty?

              section_unit = SECTION_UNITS.fetch(title.to_s) { Master::Trace::Dmesg::Report.command_unit(title) }
              Master::Trace::Dmesg::Report.render(
                unit: section_unit,
                parent: unit,
                text: [title, section.to_s].reject(&:empty?).join("\n"),
              )
            end
            [header, *body, footer].reject { |line| line.to_s.strip.empty? }.join("\n\n")
          end

          def footer
            base = if failed_stages.any?
                      "#{unit}: incomplete, failed #{failed_stages.join(", ")}"
                    elsif ok
                      "#{unit}: complete"
                    else
                      "#{unit}: complete with open findings"
                    end
            base = "#{base}, #{counts}" if counts
            skipped = Master::Io::QuotaGate.report
            skipped ? "#{base}\n\n#{skipped}" : base
          end
        end
      end
    end
  end
end
