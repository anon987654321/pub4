# frozen_string_literal: true

module Master
  # Select read strategy by file size. Reads thresholds from data/workflow.yml
  # processing_strategies block — single source of truth.
  class ProcessingStrategy
    Choice = Struct.new(:method, :context, :checkpoint, keyword_init: true)

    SMALL  = 10_240
    MEDIUM = 1_048_576

    def self.choose(file_size)
      case file_size
      when 0..SMALL          then Choice.new(method: :full_read,   context: :entire_file)
      when (SMALL + 1)..MEDIUM then Choice.new(method: :streaming, context: :line_by_line_with_lookahead)
      else                        Choice.new(method: :chunked,    context: :section_by_section, checkpoint: :per_chunk)
      end
    end
  end
end
