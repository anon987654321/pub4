#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = File.expand_path(__dir__)
APPS = %w[amber brgen bsdports hjerterom].freeze
SHARED = Pathname(ROOT).join("shared")

load SHARED.join("app/services/shared/frontend_auditor.rb")

count = (APPS + ["shared"]).sum do |app|
  root = app == "shared" ? SHARED : Pathname(ROOT).join(app)
  Shared::FrontendAuditor.call(root: root).count { |finding| %i[error warning].include?(finding.severity) }
end

abort("auditor findings: #{count}") if count.positive?

puts "auditor: 0 warnings"
