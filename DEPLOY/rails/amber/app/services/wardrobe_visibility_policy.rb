class WardrobeVisibilityPolicy
  def initialize(viewer:, owner:)
    @viewer = viewer
    @owner = owner
  end

  def can_view_wardrobe?
    return true if @viewer == @owner

    setting = @owner.privacy_setting
    return false unless setting
    return true if setting.wardrobe_public?
    return @viewer&.following?(@owner) if setting.wardrobe_followers?

    false
  end

  def can_remix_creator_wardrobe?
    @owner.creator_profile&.public? && @owner.privacy_setting&.allow_creator_remix?
  end

  def can_run_ai_analysis?
    @viewer == @owner && (@owner.privacy_setting&.allow_ai_analysis? != false)
  end
end
