# frozen_string_literal: true

require "minitest/autorun"

class AmberErasureContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(relative) = File.read(File.join(ROOT, relative))

  def test_amber_runs_a_daily_purge_after_the_deletion_grace_period
    recurring = read("RAILS/amber/config/recurring.yml")
    section = recurring.split(/^development:/).first

    assert_match(/^  purge_deleted_users:\n    class: UserPurgeJob\n    queue: bulk\n    schedule: every day at 3:50am$/m, section)
    assert_includes read("RAILS/amber/app/jobs/user_purge_job.rb"), 'where("deletion_scheduled_at <= ?", Time.current)'
  end

  def test_private_identity_and_wardrobe_rows_are_explicitly_erased
    job = read("RAILS/amber/app/jobs/user_purge_job.rb")

    %w[
      Profile CreatorProfile PrivacySetting ExternalIdentity IdentityVerification ConsentEvent
      AccountMerge Notification Shared::OutboundClick Reaction Vote Follow Connection Message LiveStream
      WearLog DeclutterReview DeclutterChallenge DeclutterOutcome Recommendation PackingList
      PlannedOutfit StylePreference Outfit Item WardrobeItem Session
    ].each do |model|
      assert_includes job, "model: \"#{model}\"", "erasure list missing #{model}"
    end
    assert_includes job, 'model: "AccountMerge", key: :guest_user_id'
    assert_includes job, 'model: "Notification", key: :actor_id'
    assert_includes job, "def nullify_review_cases(user)"
    assert_includes job, "reviewer_id: nil"
    assert_includes job, "def anonymise(user)"
    assert_includes job, "deleted_at: Time.current"
    assert_includes job, 'email_address: "purged-'
    assert_includes job, "def resolve!(name)"
    assert_includes job, 'raise "erasure table unavailable: #{name}"'
  end

  def test_public_threads_remain_but_private_item_and_outfit_links_are_removed
    job = read("RAILS/amber/app/jobs/user_purge_job.rb")

    assert_includes job, "Public posts and comments remain"
    assert_includes job, "Post.where(item_id: item_ids).update_all(item_id: nil)"
    assert_includes job, "Post.where(outfit_id: outfit_ids).update_all(outfit_id: nil)"
    assert_includes job, "CreatorWardrobeItem.where(item_id: item_ids)"
    assert_includes job, "WardrobeItem.where(item_id: item_ids)"
    assert_includes job, "Recommendation.where(item_id: item_ids)"
    assert_includes job, "DeclutterReview.where(item_id: item_ids)"
    assert_includes job, "DeclutterOutcome.where(item_id: item_ids)"
    assert_includes job, 'Comment.where(commentable_type: "Item", commentable_id: item_ids)'
    assert_includes job, 'Comment.where(commentable_type: "Outfit", commentable_id: outfit_ids)'
    assert_includes job, 'Shared::ReviewCase.where(reviewable_type: "Item", reviewable_id: item_ids)'
    assert_includes job, 'Shared::ReviewCase.where(reviewable_type: "Outfit", reviewable_id: outfit_ids)'
    assert_includes job, 'Shared::OutboundClick.where(subject_type: "Item", subject_id: item_ids)'
    assert_includes job, 'Shared::OutboundClick.where(subject_type: "Outfit", subject_id: outfit_ids)'
    assert_includes job, 'Shared::OutboundClick.where(subject_type: "Comment", subject_id: private_comment_ids)'
    assert_includes job, 'reaction_model.where(reactable_type: "Message", reactable_id: message_ids)'
    assert_includes job, 'notification_model.where(notifiable_type: "Message", notifiable_id: message_ids)'
    assert_includes job, 'Shared::OutboundClick.where(subject_type: "Message", subject_id: message_ids)'
    assert_includes job, 'Vote.where(votable_type: "Message", votable_id: message_ids)'
    assert_includes job, 'Message.where(sender_id: user.id).or(Message.where(recipient_id: user.id))'
    assert_includes job, 'destroy_each(DeclutterChallenge.where(item_id: item_ids))'
    assert_includes job, 'reaction_model.where(reactable_type: "Item", reactable_id: item_ids)'
    assert_includes job, 'notification_model.where(notifiable_type: "Item", notifiable_id: item_ids)'
    assert_includes job, 'notification_model.where(notifiable_type: "Comment", notifiable_id: private_comment_ids)'
    assert_includes job, 'reaction_model.where(reactable_type: "Comment", reactable_id: private_comment_ids)'
    assert_includes job, 'Vote.where(votable_type: "Comment", votable_id: private_comment_ids)'
    assert_includes job, 'Vote.where(votable_type: "Item", votable_id: item_ids)'
    assert_includes job, "DeclutterReview.where(item_id: item_ids)"
    assert_includes job, "DeclutterOutcome.where(item_id: item_ids)"
    refute_match(/\{ model: "Post", key: :user_id \}/, job)
    refute_match(/\{ model: "Comment", key: :user_id \}/, job)
  end

  def test_amber_schema_changes_remain_app_owned_migrations
    migrations = Dir.glob(File.join(ROOT, "RAILS/amber/db/migrate/*.rb")).map { |path| File.basename(path) }

    assert_includes migrations, "20261021230100_add_federated_identity_tables_to_amber.rb"
    assert_includes migrations, "20261021230200_add_guest_account_merges_to_amber.rb"
    refute_includes read("RAILS/amber/app/jobs/user_purge_job.rb"), "create_table"
  end
end
