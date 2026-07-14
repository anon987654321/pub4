# frozen_string_literal: true

require_relative "config/environment"
run Rails.application
Rails.application.load_server if Rails.application.respond_to?(:load_server)