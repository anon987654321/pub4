# frozen_string_literal: true

# The two guards items and outfits both need. Each fetches its record with an
# unscoped find, so each has to answer the same pair of questions: may this
# viewer change the record, and may they see it at all. The two controllers
# carried identical answers, down to the flash key; only the record and the
# index they bounce to differed, so those are the arguments.
#
# WardrobeItemsController deliberately keeps its own ownership guard: it fetches
# without preloading the owner, and its comment records why the comparison there
# must stay where a reader can see it.
module WardrobeGuards
  extend ActiveSupport::Concern

  private

  # user_id rather than user: the comparison must not depend on the owner
  # association being loaded, because strict_loading_by_default raises on a lazy
  # read and a guard that raises is a guard that never ran.
  def require_wardrobe_owner!(record, index_path)
    redirect_to(index_path, alert: t("shared.flash.not_authorized")) unless record.user_id == Current.user&.id
  end

  # Viewability, not ownership: liking someone else's outfit or browsing a
  # public wardrobe is legitimate, reading a private one is not. This reads
  # record.user and the policy reads the owner's privacy_setting, so a caller's
  # finder must preload `user: :privacy_setting` or the policy raises.
  def require_wardrobe_view!(record, index_path)
    return if WardrobeVisibilityPolicy.new(viewer: Current.user, owner: record.user).can_view_wardrobe?

    redirect_to(index_path, alert: t("shared.flash.not_authorized"))
  end
end
