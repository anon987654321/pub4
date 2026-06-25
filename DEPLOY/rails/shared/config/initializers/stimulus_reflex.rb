# frozen_string_literal: true

return unless defined?(StimulusReflex)

StimulusReflex.configure do |config|
  config.on_failed_sanity_checks = :warn
end