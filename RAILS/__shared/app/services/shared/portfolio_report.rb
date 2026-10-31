# frozen_string_literal: true

module Shared
  # The numbers `rake billing:report` prints for one app: each paid plan's
  # subscribers, revenue and funnel, and each bet's verdict. +rows+ is the
  # app's subscription relation (Shared::BillingSubscription, or master's
  # ApiKey): both carry plan_key, status, created_at and updated_at.
  # +funnel+ is { label => count } of the steps before payment, read from
  # Shared::VisitCount where the app keeps one.
  class PortfolioReport
    def initialize(app:, rows:, since:, funnel: {})
      @app = app.to_s
      @rows = rows
      @since = since
      @funnel = funnel
    end

    def lines(today:)
      [*plan_lines, "", *funnel_lines, "", *bet_lines(today)]
    end

    def paying_subscribers(plans) = entitling(plans).count

    # Monthly revenue in minor units: a yearly plan counts a twelfth of its price.
    def mrr(plans)
      entitling(plans).group(:plan_key).count.sum do |plan_key, count|
        plan = Shared::BillingPlan.find(plan_key)
        plan ? count * monthly(plan) : 0
      end
    end

    private

    def entitling(plans) = @rows.where(plan_key: plans, status: Shared::StripeBilling::ENTITLING_STATUSES)

    def monthly(plan) = plan.interval == "year" ? plan.amount / 12 : plan.amount

    def plan_lines
      header = "plans since #{@since.to_date} (subscribers, mrr, new, cancelled)"
      [header, *Shared::BillingPlan.for_app(@app).map { |plan| plan_line(plan) }]
    end

    def plan_line(plan)
      keys = [plan.key]
      started = @rows.where(plan_key: keys, created_at: @since..).count
      cancelled = @rows.where(plan_key: keys, status: "canceled", updated_at: @since..).count
      format("  %-28s %6d %10s %5d %5d", plan.key, paying_subscribers(keys), money(mrr(keys), plan.currency),
             started, cancelled)
    end

    # Each step with its share of the one before it.
    def funnel_lines
      return ["funnel: not counted in this app"] if @funnel.empty?

      previous = nil
      steps = @funnel.map do |label, count|
        rate = previous&.positive? ? format("  %5.1f%%", count * 100.0 / previous) : ""
        previous = count
        format("  %-28s %8d%s", label, count, rate)
      end
      ["funnel since #{@since.to_date}", *steps]
    end

    def bet_lines(today)
      bets = Shared::PortfolioBet.for_app(@app)
      return ["bets: none for #{@app}"] if bets.empty?

      rows = bets.map { |bet| "  #{bet.summary(public_send(bet.metric, bet.plans), today:)}" }
      ["bets (kill below the threshold at day #{bets.first.window_days})", *rows]
    end

    def money(minor, currency) = format("%.2f %s", minor / 100.0, currency)
  end
end
