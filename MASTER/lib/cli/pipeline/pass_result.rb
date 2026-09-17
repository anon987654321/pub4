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

          def render
            lines = sections.flat_map { |title, body| [title, body.to_s.chomp, ""] }
            lines << footer
            lines.join("\n")
          end

          def footer
            base = if failed_stages.any?
                      "#{unit}: incomplete — #{failed_stages.join(", ")} failed"
                    elsif ok
                      "#{unit}: complete"
                    else
                      "#{unit}: complete with open findings"
                    end
            base = "#{base}, #{counts}" if counts
            skipped = Master::Io::QuotaGate.report
            skipped ? "#{base}\n#{skipped}" : base
          end
        end
      end
    end
  end
end
