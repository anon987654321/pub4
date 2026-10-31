# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "yaml"

ROOT = File.expand_path("..", __dir__) unless defined?(ROOT)
require File.join(ROOT, "__shared/app/services/shared/stripe_billing")
require File.join(ROOT, "__shared/app/models/shared/billing_plan")
require File.join(ROOT, "__shared/app/models/shared/portfolio_bet")
require File.join(ROOT, "__shared/app/services/shared/portfolio_report")

# The bets in __shared/config/portfolio.yml: each names real plans of its app
# and a metric the report can compute, and the keep-or-kill rule holds.
# Bare ruby, no Rails: the report runs over an in-memory stand-in for the
# subscription relation.
class PortfolioContractTest < Minitest::Test
  # The slice of an ActiveRecord relation PortfolioReport uses.
  class Rows
    def initialize(rows) = @rows = rows

    def where(**conditions)
      Rows.new(@rows.select { |row| conditions.all? { |column, wanted| match?(row[column], wanted) } })
    end

    def group(column) = Grouped.new(@rows.group_by { |row| row[column] })

    def count = @rows.size

    private

    def match?(value, wanted)
      case wanted
      when Array then wanted.include?(value)
      when Range then wanted.cover?(value)
      else value == wanted
      end
    end
  end

  Grouped = Struct.new(:groups) do
    def count = groups.transform_values(&:size)
  end

  def test_every_bet_names_plans_of_its_own_app
    Shared::PortfolioBet.all.each do |bet|
      refute_empty bet.plans, bet.key
      bet.plans.each { |key| assert_equal bet.app, Shared::BillingPlan.find(key)&.app, "#{bet.key} plan #{key}" }
    end
  end

  def test_every_bet_is_decided_by_a_known_metric_against_a_positive_threshold
    Shared::PortfolioBet.all.each do |bet|
      name = bet.key
      assert_includes Shared::PortfolioBet.metrics, bet.metric, name
      assert_operator bet.below, :>, 0, name
      refute_empty bet.hypothesis.strip, name
    end
  end

  def test_every_plan_belongs_to_a_bet
    planned = Shared::PortfolioBet.all.flat_map(&:plans)
    Shared::BillingPlan.all.each { |plan| assert_includes planned, plan.key, "#{plan.key} is in no bet" }
  end

  def test_a_bet_runs_its_window_then_is_kept_or_killed_on_its_number
    bet = Shared::PortfolioBet.all.first.with(started_on: Date.new(2026, 1, 1), below: 5, window_days: 90)

    assert_equal :not_launched, bet.with(started_on: nil).verdict(100, today: Date.new(2027, 1, 1))
    assert_equal :running, bet.verdict(0, today: Date.new(2026, 3, 31))
    assert_equal :kill, bet.verdict(4, today: Date.new(2026, 4, 1))
    assert_equal :keep, bet.verdict(5, today: Date.new(2026, 4, 1))
  end

  def test_the_report_counts_only_paying_rows_and_a_yearly_plan_as_a_twelfth
    now = Time.now
    rows = Rows.new([
      { plan_key: "amber_premium_monthly", status: "active", created_at: now, updated_at: now },
      { plan_key: "amber_premium_yearly", status: "trialing", created_at: now, updated_at: now },
      { plan_key: "amber_premium_monthly", status: "past_due", created_at: now, updated_at: now },
      { plan_key: "amber_premium_monthly", status: "canceled", created_at: now, updated_at: now },
    ])
    funnel = { "views" => 10, "paid" => 2 }
    report = Shared::PortfolioReport.new(app: "amber", rows:, since: now - 86_400, funnel:)
    plans = %w[amber_premium_monthly amber_premium_yearly]

    assert_equal 2, report.paying_subscribers(plans)
    assert_equal 799 + (6900 / 12), report.mrr(plans)
    text = report.lines(today: Date.today).join("\n")
    assert_match(/amber_premium\s+not_launched paying_subscribers 2 of 20/, text)
    assert_match(/paid\s+2\s+20\.0%/, text)
  end
end
