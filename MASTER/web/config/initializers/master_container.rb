# frozen_string_literal: true
# Pre-build container at boot to avoid blocking Falcons async event loop.
Rails.application.config.after_initialize do
  Thread.new { ApplicationController.class_eval { container } rescue nil }
end
