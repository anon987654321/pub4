# frozen_string_literal: true

require "date"
require "yaml"

module Shared
  # One bet from config/portfolio.yml and the rule that decides it: kept or
  # killed on one number once its window has run. Plain Ruby, so the rule is
  # tested without booting an app; +today+ is always passed, as Date.current.
  PortfolioBet = Data.define(:key, :app, :plans, :started_on, :metric, :below, :hypothesis, :window_days) do
    def self.metrics = %w[paying_subscribers mrr]

    def self.all
      @all ||= begin
        catalogue = YAML.safe_load_file(File.expand_path("../../../config/portfolio.yml", __dir__),
                                        permitted_classes: [Date])
        window_days = Integer(catalogue.fetch("kill_after_days"))
        catalogue.fetch("bets").map { |key, row| from_row(key, row, window_days:) }
      end
    end

    def self.from_row(key, row, window_days:)
      started = row["started_on"]
      metric = row.fetch("metric")
      raise ArgumentError, "#{key}: unknown metric #{metric}" unless metrics.include?(metric)

      new(key:, app: row.fetch("app"), plans: Array(row.fetch("plans")), metric:,
          started_on: started && Date.parse(started.to_s), below: Integer(row.fetch("below")),
          hypothesis: row.fetch("hypothesis"), window_days:)
    end

    def self.for_app(app) = all.select { |bet| bet.app == app.to_s }

    def review_on = started_on && (started_on + window_days)

    # :not_launched, :running, :keep or :kill for +value+ of the bet's metric.
    def verdict(value, today:)
      return :not_launched unless started_on
      return :running if today < review_on

      value >= below ? :keep : :kill
    end

    # One report line: the verdict, the number against its threshold, the clock.
    def summary(value, today:)
      clock = started_on ? "day #{(today - started_on).to_i}, review #{review_on}" : "no start date"
      format("%-26s %-12s %s %d of %d (%s)", key, verdict(value, today:), metric, value, below, clock)
    end
  end
end
