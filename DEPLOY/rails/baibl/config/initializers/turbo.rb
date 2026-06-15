# frozen_string_literal: true
# AN407: Turbo progress bar customization

Rails.application.config.after_initialize do
  next unless defined?(Turbo)

  Turbo.config.drive.progressBarDelay = 100
end