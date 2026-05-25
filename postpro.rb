# frozen_string_literal: true

class Postpro
  def self.process_media(record, &block)
    record.update!(lifecycle_state: "processing")
    block.call
    record.update!(lifecycle_state: "completed")
  rescue StandardError => e
    record.update!(lifecycle_state: "failed")
    raise e
  end
end
