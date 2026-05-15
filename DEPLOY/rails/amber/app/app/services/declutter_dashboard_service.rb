class DeclutterDashboardService
  def initialize(user)
    @user = user
  end

  def summary
    items = @user.items
    active = items.active_wardrobe
    released = items.where(lifecycle_state: %w[released donated sold recycled])

    {
      total_items: items.count,
      active_items: active.count,
      declutter_box: items.declutter_box.count,
      sentimental_archive: items.sentimental.count,
      released_items: released.count,
      never_worn: active.never_worn.count,
      duplicate_groups: DuplicateDetectorService.new(@user).groups.count,
      amount_recovered: @user.declutter_outcomes.sum(:amount_recovered),
      top_candidates: top_candidates(active),
      matrix: matrix(active)
    }
  end

  private

  def top_candidates(scope)
    scope.to_a.sort_by { |item| -item.declutter_score[:total_release_score] }.first(12)
  end

  def matrix(scope)
    scope.group_by { |item| item.declutter_score[:quadrant] }.transform_values(&:count)
  end
end
