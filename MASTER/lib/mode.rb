# frozen_string_literal: true

module Mode
  MODES = %i[read write append].freeze

  def self.valid?(mode)
    MODES.include?(mode.to_sym)
  end
end