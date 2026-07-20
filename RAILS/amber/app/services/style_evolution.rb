# frozen_string_literal: true

class StyleEvolution
  PHASE_ORDER = Item::LIFE_PHASES

  def initialize(user)
    @user = user
  end

  def timeline
    {
      phases: phase_groups,
      wear_events: wear_timeline,
      summary: phase_summary,
    }
  end

  private

  attr_reader :user

  def items
    @items ||= user.items.active_wardrobe.includes(:wear_logs).order(created_at: :asc)
  end

  def phase_groups
    PHASE_ORDER.map do |phase|
      grouped = items.select { |item| item.life_phase == phase }
      {
        phase:,
        label: phase_label(phase),
        count: grouped.size,
        items: grouped.map { |item| item_snapshot(item) }
      }
    end
  end

  def wear_timeline
    WearLog.where(user:)
      .includes(:item, :outfit)
      .recent
      .limit(40)
      .map do |log|
        {
          worn_on: log.worn_on,
          item_title: log.item.title,
          item_id: log.item_id,
          life_phase: log.item.life_phase,
          outfit_title: log.outfit&.title,
          context: log.context
        }
      end
  end

  def phase_summary
    counts = items.group_by(&:life_phase).transform_values(&:size)
    dominant = counts.max_by { |_, size| size }&.first
    {
      total_items: items.size,
      phased_items: items.count { |item| item.life_phase.present? },
      dominant_phase: dominant,
      unphased_items: items.count { |item| item.life_phase.blank? }
    }
  end

  def item_snapshot(item)
    {
      id: item.id,
      title: item.title,
      category: item.category,
      mood_effect: item.mood_effect,
      times_worn: item.times_worn.to_i,
      purchase_date: item.purchase_date,
      created_at: item.created_at&.to_date
    }
  end

  def phase_label(phase)
    {
      "current" => "Current self",
      "past-self" => "Past self",
      "aspirational" => "Aspirational"
    }.fetch(phase, phase.humanize)
  end
end
