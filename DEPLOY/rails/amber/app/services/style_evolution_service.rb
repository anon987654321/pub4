# frozen_string_literal: true

class StyleEvolutionService
  def self.timeline_for(user)
    new(user).timeline
  end

  def initialize(user)
    @user = user
  end

  def timeline
    wear_logs = @user.items.joins(:wear_logs).group("strftime('%Y-%m', wear_logs.worn_on)")
                     .order(Arel.sql("strftime('%Y-%m', wear_logs.worn_on)"))
                     .count

    color_trend = @user.items.where.not(color: [nil, ""]).group(:color).order(Arel.sql("COUNT(*) DESC")).count.first(5)
    aesthetic_phases = wear_logs.map do |month, count|
      { month:, wears: count, phase: phase_label(count) }
    end

    {
      aesthetic_phases: aesthetic_phases,
      dominant_colors: color_trend,
      underused_count: @user.items.active_wardrobe.never_worn.count
    }
  end

  private

  def phase_label(wears)
    case wears
    when 0..2 then "quiet"
    when 3..8 then "building"
    else "peak"
    end
  end
end