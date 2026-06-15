# frozen_string_literal: true

class ActivityEventRecorder
  def self.call(**kwargs)
    Shared::ActivityEventRecorder.call(**kwargs)
  end
end