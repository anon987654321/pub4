# frozen_string_literal: true

# The law API's half of `rake billing:report` (RAILS/__shared/lib/tasks/billing.rake
# is the brgen and amber half). master keeps no visit counts, so its funnel is
# the keys bought.
namespace :billing do
  desc "Law API plans and the bet they are over N days: rake billing:report[30]"
  task :report, [:days] => :environment do |_, args|
    since = (args[:days].presence || 30).to_i.days.ago
    funnel = { "keys bought" => ApiKey.where(created_at: since..).count }
    report = Shared::PortfolioReport.new(app: "master", rows: ApiKey.all, since:, funnel:)
    puts report.lines(today: Date.current)
  end
end
