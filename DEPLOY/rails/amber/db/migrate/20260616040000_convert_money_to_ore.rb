# frozen_string_literal: true

class ConvertMoneyToOre < ActiveRecord::Migration[8.1]
  def up
    add_column :items, :price_cents, :integer

    execute <<~SQL.squish
      UPDATE items SET price_cents = CAST(ROUND(price * 100) AS INTEGER) WHERE price IS NOT NULL
    SQL

    remove_column :items, :price

    add_column :declutter_outcomes, :amount_recovered_cents, :integer

    execute <<~SQL.squish
      UPDATE declutter_outcomes
      SET amount_recovered_cents = CAST(ROUND(amount_recovered * 100) AS INTEGER)
      WHERE amount_recovered IS NOT NULL
    SQL

    remove_column :declutter_outcomes, :amount_recovered

    add_column :sustainability_metrics, :repair_cost_estimate_cents, :integer
    add_column :sustainability_metrics, :resale_value_cents, :integer

    execute <<~SQL.squish
      UPDATE sustainability_metrics
      SET repair_cost_estimate_cents = CAST(ROUND(repair_cost_estimate * 100) AS INTEGER)
      WHERE repair_cost_estimate IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE sustainability_metrics
      SET resale_value_cents = CAST(ROUND(resale_value * 100) AS INTEGER)
      WHERE resale_value IS NOT NULL
    SQL

    remove_column :sustainability_metrics, :repair_cost_estimate
    remove_column :sustainability_metrics, :resale_value
  end

  def down
    add_column :items, :price, :decimal
    execute "UPDATE items SET price = price_cents / 100.0 WHERE price_cents IS NOT NULL"
    remove_column :items, :price_cents

    add_column :declutter_outcomes, :amount_recovered, :decimal, precision: 10, scale: 2
    execute "UPDATE declutter_outcomes SET amount_recovered = amount_recovered_cents / 100.0 WHERE amount_recovered_cents IS NOT NULL"
    remove_column :declutter_outcomes, :amount_recovered_cents

    add_column :sustainability_metrics, :repair_cost_estimate, :decimal, precision: 10, scale: 2
    add_column :sustainability_metrics, :resale_value, :decimal, precision: 10, scale: 2
    execute "UPDATE sustainability_metrics SET repair_cost_estimate = repair_cost_estimate_cents / 100.0 WHERE repair_cost_estimate_cents IS NOT NULL"
    execute "UPDATE sustainability_metrics SET resale_value = resale_value_cents / 100.0 WHERE resale_value_cents IS NOT NULL"
    remove_column :sustainability_metrics, :repair_cost_estimate_cents
    remove_column :sustainability_metrics, :resale_value_cents
  end
end
