# frozen_string_literal: true

require "test_helper"

# Money in this app is stored in ore and read through MoneyInOre, and this is
# the one model that carries two money columns. Both are nullable -- a garment
# whose resale value nobody has estimated is the normal case, and a validation
# that refused nil would make the metric unwritable until someone guessed.
class SustainabilityMetricTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "sm@amber.test", password: "password123")
    @item = Item.create!(user: @user, title: "Wool coat", category: "Outerwear")
  end

  def metric(**overrides) = SustainabilityMetric.new({ item: @item }.merge(overrides))

  test "a metric belongs to a garment" do
    assert_not SustainabilityMetric.new.valid?
    assert metric.valid?
  end

  # An unestimated value is the normal case, not an error.
  test "every figure is optional" do
    assert metric.valid?
    assert_nil metric.resale_value_cents
  end

  test "no figure may be negative" do
    assert_not metric(resale_value_cents: -1).valid?
    assert_not metric(repair_cost_estimate_cents: -1).valid?
    assert_not metric(environmental_score: -1).valid?
  end

  test "zero is a real answer" do
    assert metric(resale_value_cents: 0, repair_cost_estimate_cents: 0, environmental_score: 0).valid?
  end

  test "money is read back in kroner from ore" do
    record = metric(resale_value_cents: 45_000, repair_cost_estimate_cents: 12_50)

    assert_in_delta 450.0, record.resale_value.to_f, 0.01
    assert_in_delta 12.5, record.repair_cost_estimate.to_f, 0.01
  end

  test "an unestimated value reads back as nothing rather than as zero kroner" do
    assert_nil metric.resale_value, "nil and 0,00 kr are different claims about a garment"
  end

  # --- what it says about the garment ---------------------------------------

  test "a garment nobody has worn is unused" do
    assert metric.unused?
  end

  test "one wear is enough to stop being unused" do
    @item.update!(times_worn: 1)

    assert_not metric.unused?
  end

  test "a null wear count reads as unused rather than raising" do
    @item.update!(times_worn: nil)

    assert metric.unused?
  end

  test "cost per wear is the garment's own figure, not a second one" do
    @item.update!(price_cents: 60_000, times_worn: 4)

    assert_equal @item.cost_per_wear, metric.cost_per_wear
    assert_in_delta 150.0, metric.cost_per_wear, 0.01
  end

  test "an unworn garment has no cost per wear here either" do
    @item.update!(price_cents: 60_000, times_worn: 0)

    assert_nil metric.cost_per_wear
  end

  test "a garment carries at most one metric" do
    metric.save!

    assert_equal 1, SustainabilityMetric.where(item: @item).count
    assert_equal SustainabilityMetric.where(item: @item).first,
                 Item.where(id: @item.id).includes(:sustainability_metric).first.sustainability_metric
  end

  test "destroying a garment takes its metric" do
    metric.save!

    assert_difference "SustainabilityMetric.count", -1 do
      @item.destroy!
    end
  end
end
