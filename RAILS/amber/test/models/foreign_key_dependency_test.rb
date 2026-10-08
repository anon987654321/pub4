# frozen_string_literal: true

require "test_helper"

# destroy_cascade_test.rb asks whether a declared cascade can load what it must
# delete. This asks the question one step earlier: whether the cascade is
# declared at all.
#
# The schema has fifty-four foreign keys. Sixteen of them point at a parent
# whose model declares no association with a `dependent:` option, and SQLite
# enforces the constraint, so `parent.destroy` on any of those raises
# ActiveRecord::InvalidForeignKey — a 500 on a delete button, not a validation
# error a form can show.
#
# Three were reachable from ordinary use and are fixed:
#
#   delete an outfit you have worn      Outfit -> WearLog
#   delete an outfit you have planned   Outfit -> PlannedOutfit
#   delete a garment on a packing list  Item   -> PackingListItem
#
# The rest are recorded below rather than guessed at. Choosing between destroy
# and nullify is a statement about what the record means once its parent is
# gone, and that is not a decision to make in bulk.
class ForeignKeyDependencyTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "fk@amber.test", password: "password123")
    @outfit = Outfit.create!(user: @user, name: "Rain day")
    @item = Item.create!(user: @user, title: "Wool coat", category: "Outerwear")
  end

  # --- the three that were live 500s ---------------------------------------

  test "an outfit that has been worn can be deleted" do
    WearLog.create!(user: @user, item: @item, outfit: @outfit, worn_on: Date.current)

    assert_nothing_raised { @outfit.destroy! }
  end

  # A wear happened. Deleting the outfit deletes the grouping, not the history —
  # the garment's times_worn already counts it.
  test "deleting an outfit keeps the wear history and releases it" do
    log = WearLog.create!(user: @user, item: @item, outfit: @outfit, worn_on: Date.current)

    assert_no_difference "WearLog.count" do
      @outfit.destroy!
    end
    assert_nil log.reload.outfit_id, "the wear log still points at an outfit that is gone"
  end

  test "an outfit that has been planned can be deleted" do
    PlannedOutfit.create!(user: @user, outfit: @outfit, planned_date: Date.current)

    assert_difference "PlannedOutfit.count", -1 do
      assert_nothing_raised { @outfit.destroy! }
    end
  end

  test "a garment on a packing list can be deleted" do
    list = PackingList.create!(user: @user, name: "Oslo", starts_on: Date.current, ends_on: Date.current)
    PackingListItem.create!(packing_list: list, item: @item)

    assert_difference "PackingListItem.count", -1 do
      assert_nothing_raised { @item.destroy! }
    end
    assert PackingList.exists?(list.id), "losing a garment deleted the whole trip"
  end

  # --- the inventory --------------------------------------------------------

  # Every foreign key whose parent model declares no dependent option. An entry
  # is a statement that someone looked and left it; a gap that is not here is one
  # that arrived unnoticed, and it is a 500 waiting on a delete button.
  KNOWN_GAPS = [
    # Framework-owned. ActiveStorage deletes variant records through
    # Blob#purge and its own jobs rather than through a dependent option, and
    # this app does not get to choose otherwise.
    "ActiveStorage::Blob -> ActiveStorage::VariantRecord (blob_id)",
    "Item -> CreatorWardrobeItem (item_id)",
    "Item -> Post (item_id)",
    "Item -> Recommendation (item_id)",
    "Item -> WardrobeItem (item_id)",
    "Outfit -> DeclutterChallenge (outfit_id)",
    "Outfit -> Post (outfit_id)",
    "Outfit -> Recommendation (outfit_id)",
    "User -> Shared::Notification (actor_id)",
    "User -> Shared::Notification (user_id)",
    "User -> Shared::Reaction (user_id)",
    "User -> Shared::ReviewCase (reporter_id)",
    "User -> Shared::ReviewCase (reviewer_id)",
    "User -> WardrobeItem (user_id)",
    "User -> WearLog (user_id)"
  ].freeze

  def uncovered_foreign_keys
    Rails.application.eager_load!
    models = ActiveRecord::Base.descendants.reject(&:abstract_class?).select do |model|
      model.table_exists?
    rescue StandardError # scan: intentional — a model without a table is excluded; false is the filter answer
      false
    end
    by_table = models.index_by(&:table_name)

    models.flat_map do |model|
      ActiveRecord::Base.connection.foreign_keys(model.table_name).filter_map do |key|
        parent = by_table[key.to_table]
        next unless parent

        covered = parent.reflect_on_all_associations.any? do |reflection|
          reflection.options[:dependent] && (reflection.klass == model rescue false)
        end
        "#{parent.name} -> #{model.name} (#{key.column})" unless covered
      end
    end.sort
  end

  def test_no_new_foreign_key_is_left_without_a_dependent_option
    new_gaps = uncovered_foreign_keys - KNOWN_GAPS

    assert_empty new_gaps,
                 "these foreign keys have no dependent option on the parent, so destroying the " \
                 "parent raises InvalidForeignKey — a 500, not a form error:\n  #{new_gaps.join("\n  ")}"
  end

  # The other direction: a gap that has been closed must leave the list, or the
  # list stops being a description of the tree.
  def test_the_known_gaps_are_still_gaps
    closed = KNOWN_GAPS - uncovered_foreign_keys

    assert_empty closed, "these are covered now — remove them from KNOWN_GAPS:\n  #{closed.join("\n  ")}"
  end

  # The instrument: if the scan stops finding foreign keys at all, both tests
  # above pass having measured nothing.
  def test_the_scan_reads_the_schema
    Rails.application.eager_load!
    total = ActiveRecord::Base.descendants.reject(&:abstract_class?).sum do |model|
      model.table_exists? ? ActiveRecord::Base.connection.foreign_keys(model.table_name).size : 0
    rescue StandardError
      0
    end

    assert_operator total, :>, 30, "the foreign-key scan is returning almost nothing"
  end
end
