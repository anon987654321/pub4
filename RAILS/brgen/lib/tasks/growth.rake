# frozen_string_literal: true

namespace :growth do
  desc "Report first-party growth signals without collecting per-request identity"
  task report: :environment do |_, args|
    days = (args[:days] || 30).to_i.clamp(1, 365)
    puts Shared::GrowthReport.new(window: days.days).render
  end
end
