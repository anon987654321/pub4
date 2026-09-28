# frozen_string_literal: true

module Shared
  module BuildInfoHelper
    def app_version
      ENV["APP_VERSION"].presence || "development"
    end

    def app_revision
      if Rails.application.respond_to?(:revision)
        Rails.application.revision.to_s.presence
      end || ENV["SOURCE_REVISION"].presence || "working-tree"
    rescue StandardError
      ENV["SOURCE_REVISION"].presence || "working-tree"
    end
  end
end
