# frozen_string_literal: true

require "test_helper"

# Which association reads actually raise under strict_loading_by_default, pinned
# by running them rather than by reading the model.
#
# ApplicationRecord sets strict_loading_by_default = true, but
# Shared::CascadingAssociationsLoad — declared three lines below it — sets
# strict_loading: false on every has_many/has_one carrying a :destroy,
# :destroy_async, :delete_all or :nullify cascade. So on Item, the four
# associations that look most dangerous (declutter_review, declutter_challenges,
# sustainability_metric, garment_embedding) are all exempt and do NOT raise.
#
# `belongs_to :user` is not wrapped, and does. That is the read that bites jobs:
# they have no request spec, and a job that raises on its first record simply
# never does its work. Both jobs below read item.user.
class StrictLoadingJobPathsTest < ActiveSupport::TestCase
  def make_item
    user = User.strict_loading(false).create!(
      email_address: "job-#{SecureRandom.hex(4)}@example.test", password: "password"
    )
    Item.strict_loading(false).create!(
      user: user, title: "Wool coat", category: "outerwear",
      lifecycle_state: "declutter_box", times_worn: 0, price_cents: 0
    )
  end

  # The distinction this file exists to hold. If a future change drops the
  # cascade concern, these four start raising and this test says which.
  def test_cascading_associations_are_exempt_from_strict_loading
    fresh = Item.find(make_item.id)

    exempt = %i[declutter_review declutter_challenges sustainability_metric garment_embedding]
    raising = exempt.reject do |assoc|
      fresh.public_send(assoc)
      true
    rescue ActiveRecord::StrictLoadingViolationError
      false
    end

    assert_empty raising, "CascadingAssociationsLoad no longer covers #{raising.join(', ')}"
  end

  def test_belongs_to_user_still_raises_on_a_bare_find
    fresh = Item.find(make_item.id)

    assert_raises(ActiveRecord::StrictLoadingViolationError) { fresh.user }
  end

  # The two jobs that read it. Neither had any coverage, which is why a raise
  # here would have been invisible.
  def test_fingerprint_job_runs_without_a_strict_loading_violation
    item = make_item
    assert_nothing_raised { FingerprintGarmentJob.new.perform(item.id) }
  end

  def test_declutter_hygiene_job_runs_without_a_strict_loading_violation
    make_item.update_column(:metadata, { "declutter_box_at" => 45.days.ago.to_date.iso8601 })
    assert_nothing_raised { DeclutterHygieneJob.new.perform }
  end
end
