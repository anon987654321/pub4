# frozen_string_literal: true

# The read surface for paid plans and the bets they are (config/portfolio.yml).
# A rake task for the reason visits.rake gives: it answers "keep or kill"
# when that is being decided, not continuously.
namespace :billing do
  desc "Paid plans, the funnel and each bet's verdict over N days: rake billing:report[30]"
  task :report, [:days] => :environment do |_, args|

    since = (args[:days].presence || 30).to_i.days.ago
    views = Shared::VisitCount.since(since.to_date)
    funnel = {
      "billing page views" => views.where(route: "billing#show").sum(:count),
      "checkouts started" => views.where(route: "billing#create").sum(:count),
      "subscriptions started" => Shared::BillingSubscription.where(created_at: since..).count,
    }
    # Each app names itself once, in its BillingController.
    report = Shared::PortfolioReport.new(app: BillingController.billing_app, rows: Shared::BillingSubscription.all,
                                         since:, funnel:)
    puts report.lines(today: Date.current)
  end
end
