# frozen_string_literal: true

require "test_helper"

class UserPurgeJobTest < ActiveJob::TestCase
  setup do
    @suffix = SecureRandom.hex(6)
    @user = User.create!(email_address: "erase-#{@suffix}@amber.test", password: "password123")
    @other = User.create!(email_address: "keep-#{@suffix}@amber.test", password: "password123")
    @provider = IdentityProvider.create!(name: "BankID", slug: "bankid-#{@suffix}")
  end

  def schedule_purge!
    @user.update_columns(
      deleted_at: Time.current,
      deletion_scheduled_at: 1.second.ago,
      email_verification_token: "verify-#{@suffix}",
      magic_link_token: "magic-#{@suffix}",
      magic_link_expires_at: 1.hour.from_now,
      otp_secret: "otp-secret",
      remember_token: "remember-secret"
    )
  end

  test "erasure anonymises the account and destroys private identity and wardrobe data" do
    profile = Profile.find_by!(user_id: @user.id)
    profile.update!(display_name: "Private Display Name", location: "Bergen")
    profile.avatar.attach(io: StringIO.new("profile-image"), filename: "avatar.jpg", content_type: "image/jpeg")

    item = Item.create!(user: @user, title: "Private wool coat", category: "Outerwear")
    item.photos.attach(io: StringIO.new("wardrobe-image"), filename: "coat.jpg", content_type: "image/jpeg")
    wardrobe_item = WardrobeItem.create!(user: @user, item: item, notes: "Personal notes")
    other_item_review = DeclutterReview.create!(
      user: @other, item: item, reason_kept: "memory", decision: "keep", notes: "Other user's private item review"
    )
    other_item_outcome = DeclutterOutcome.create!(
      user: @other, item: item, action: "sold", notes: "Other user's reference to item"
    )
    outfit = Outfit.create!(user: @user, name: "Private occasion outfit")
    outfit.image.attach(io: StringIO.new("outfit-image"), filename: "outfit.jpg", content_type: "image/jpeg")

    item_blob_ids = ActiveStorage::Attachment.where(record_type: "Item", record_id: item.id, name: "photos").pluck(:blob_id)
    profile_blob_ids = ActiveStorage::Attachment.where(record_type: "Profile", record_id: profile.id, name: "avatar").pluck(:blob_id)
    outfit_blob_ids = ActiveStorage::Attachment.where(record_type: "Outfit", record_id: outfit.id, name: "image").pluck(:blob_id)

    public_post = Post.create!(user: @user, body: "Public outfit post", item: item, outfit: outfit)
    other_post = Post.create!(user: @other, body: "A post using the shared item", item: item, outfit: outfit)
    private_item_click = Shared::OutboundClick.create!(
      app: "amber", url_host: "merchant.example", subject_type: "Item", subject_id: item.id,
      user_id: @other.id, guest: false, created_at: Time.current
    )
    private_comment_click = Shared::OutboundClick.create!(
      app: "amber", url_host: "merchant.example", subject_type: "Comment", subject_id: 987_654,
      user_id: @other.id, guest: false, created_at: Time.current
    )
    user_click = Shared::OutboundClick.create!(
      app: "amber", url_host: "merchant.example", user_id: @user.id, guest: false, created_at: Time.current
    )
    preserved_comment = Comment.create!(user: @user, commentable: other_post, content: "A public comment")
    private_item_comment = Comment.create!(user: @other, commentable: item, content: "Comment on private item")
    private_outfit_comment = Comment.create!(user: @other, commentable: outfit, content: "Comment on private outfit")
    private_comment_click.update!(subject_id: private_item_comment.id)
    private_comment_reaction = Shared::Reaction.create!(
      user: @other, reactable: private_item_comment, kind: "love"
    )
    private_comment_notification = Shared::Notification.create!(
      user: @other, actor: @other, notifiable: private_outfit_comment, kind: "reply"
    )
    private_comment_vote = Vote.create!(user: @other, votable: private_item_comment, value: 1)
    item_review = Shared::ReviewCase.create!(
      reviewable: item, reporter: @other, reviewer: @user, state: "closed", reason: "other"
    )
    outfit_review = Shared::ReviewCase.create!(
      reviewable: outfit, reporter: @other, reviewer: @user, state: "closed", reason: "other"
    )
    reporter_review = Shared::ReviewCase.create!(
      reviewable: other_post, reporter: @user, state: "open", reason: "other"
    )
    retained_review = Shared::ReviewCase.create!(
      reviewable: other_post, reporter: @other, reviewer: @user, state: "closed", reason: "other"
    )

    provider_identity = ExternalIdentity.create!(
      user: @user, identity_provider: @provider, subject: "subject-#{@suffix}",
      email_address: @user.email_address, assurance_level: "verified"
    )
    merge_as_destination = AccountMerge.create!(guest_user: @other, user: @user, status: "merged", merged_at: Time.current)
    merge_as_guest = AccountMerge.create!(guest_user: @user, user: @other, status: "merged", merged_at: Time.current)
    session = @user.sessions.create!(user_agent: "private browser", ip_address: "192.0.2.44")

    sent = Message.create!(sender: @user, recipient: @other, body: "Private message sent")
    received = Message.create!(sender: @other, recipient: @user, body: "Private message received")
    private_message_reaction = Shared::Reaction.create!(user: @other, reactable: sent, kind: "love")
    private_message_notification = Shared::Notification.create!(
      user: @other, actor: @other, notifiable: received, kind: "message"
    )
    private_message_vote = Vote.create!(user: @other, votable: received, value: 1)
    private_message_click = Shared::OutboundClick.create!(
      app: "amber", url_host: "merchant.example", subject_type: "Message", subject_id: sent.id,
      user_id: @other.id, guest: false, created_at: Time.current
    )
    Follow.create!(follower: @user, followee: @other)
    Follow.create!(follower: @other, followee: @user)
    Connection.create!(requester: @user, addressee: @other, status: "accepted")
    Shared::Reaction.create!(user: @user, reactable: item, kind: "like")
    private_item_reaction = Shared::Reaction.create!(user: @other, reactable: item, kind: "love")
    private_outfit_reaction = Shared::Reaction.create!(user: @other, reactable: outfit, kind: "love")
    Shared::Notification.create!(user: @user, actor: @other, kind: "alert")
    Shared::Notification.create!(user: @other, actor: @user, kind: "follow")
    private_item_notification = Shared::Notification.create!(
      user: @other, actor: @other, notifiable: item, kind: "reaction"
    )
    private_outfit_notification = Shared::Notification.create!(
      user: @other, actor: @other, notifiable: outfit, kind: "reaction"
    )
    private_item_vote = Vote.create!(user: @other, votable: item, value: 1)
    private_outfit_vote = Vote.create!(user: @other, votable: outfit, value: 1)

    other_creator = CreatorProfile.create!(
      user: @other, handle: "creator-#{@suffix}", display_name: "Other creator", public: true
    )
    creator_entry = CreatorWardrobeItem.create!(creator_profile: other_creator, item: item, caption: "Shared item")
    other_recommendation = Recommendation.create!(user: @other, item: item, kind: "declutter", reason: "A recommendation")
    other_challenge = DeclutterChallenge.create!(
      user: @other, item: Item.create!(user: @other, title: "Other garment", category: "Tops"),
      outfit: outfit, due_on: Date.current, status: "pending"
    )
    other_item_challenge = DeclutterChallenge.create!(
      user: @other, item: item, due_on: Date.current, status: "pending"
    )

    original_password_digest = @user.password_digest
    schedule_purge!
    UserPurgeJob.perform_now

    @user.reload
    assert_equal "purged-#{@user.id}@deleted.invalid", @user.email_address
    assert_not_nil @user.deleted_at
    assert_nil @user.deletion_scheduled_at
    %i[email_verification_token magic_link_token magic_link_expires_at otp_secret remember_token].each do |field|
      assert_nil @user.public_send(field), "#{field} survived erasure"
    end
    assert_not_nil @user.password_digest
    refute_equal original_password_digest, @user.password_digest, "old password credential survived erasure"
    refute Session.exists?(id: session.id)
    assert_empty Session.where(user_id: @user.id)

    assert_not Profile.exists?(profile.id), "profile survived erasure"
    assert_not Item.exists?(item.id), "private item survived erasure"
    assert_not DeclutterReview.exists?(other_item_review.id), "another user's review retained a deleted item"
    assert_not DeclutterOutcome.exists?(other_item_outcome.id), "another user's outcome retained a deleted item"
    assert_not Outfit.exists?(outfit.id), "private outfit survived erasure"
    assert_not WardrobeItem.exists?(wardrobe_item.id), "wardrobe record survived erasure"
    assert_not ExternalIdentity.exists?(provider_identity.id), "provider subject survived erasure"
    assert_not AccountMerge.exists?(merge_as_destination.id), "merge audit by destination survived erasure"
    assert_not AccountMerge.exists?(merge_as_guest.id), "merge audit by guest survived erasure"
    assert_not CreatorWardrobeItem.exists?(creator_entry.id), "creator reference to private item survived erasure"
    assert_not Recommendation.exists?(other_recommendation.id), "recommendation leaked a private item"
    assert_nil other_challenge.reload.outfit_id, "another account's challenge retained the deleted outfit id"
    assert_empty Message.where(id: [ sent.id, received.id ]), "private inbox messages survived erasure"
    refute Shared::Reaction.exists?(private_message_reaction.id), "reaction retained a private message target"
    refute Shared::Notification.exists?(private_message_notification.id), "notification retained a private message target"
    refute Vote.exists?(private_message_vote.id), "vote retained a private message target"
    refute Shared::OutboundClick.exists?(private_message_click.id), "outbound click retained a private message target"
    assert_empty Follow.where("follower_id = :id OR followee_id = :id", id: @user.id)
    assert_empty Connection.where("requester_id = :id OR addressee_id = :id", id: @user.id)
    assert_empty Shared::Reaction.where(user_id: @user.id)
    assert_not Shared::Reaction.exists?(private_item_reaction.id), "another user's reaction to a private item survived"
    assert_not Shared::Reaction.exists?(private_outfit_reaction.id), "another user's reaction to a private outfit survived"
    assert_empty Shared::Notification.where("user_id = :id OR actor_id = :id", id: @user.id)
    assert_not Shared::Notification.exists?(private_item_notification.id), "notification retained a private item target"
    assert_not Shared::Notification.exists?(private_outfit_notification.id), "notification retained a private outfit target"
    assert_not Vote.exists?(private_item_vote.id), "vote retained a private item target"
    assert_not Vote.exists?(private_outfit_vote.id), "vote retained a private outfit target"
    assert_not Shared::OutboundClick.exists?(user_click.id), "outbound click tied to erased account survived"
    assert_not Shared::OutboundClick.exists?(private_item_click.id), "outbound click retained a private item target"
    assert_not Shared::OutboundClick.exists?(private_comment_click.id), "outbound click retained a private comment target"
    refute DeclutterChallenge.exists?(other_item_challenge.id), "another user's challenge retained a deleted item"

    [ *profile_blob_ids, *item_blob_ids, *outfit_blob_ids ].each do |blob_id|
      assert_empty ActiveStorage::Attachment.where(blob_id: blob_id), "an erased user's attachment survived"
    end

    public_post = Post.includes(:user).find(public_post.id)
    other_post = Post.includes(:user).find(other_post.id)
    assert_equal "Public outfit post", public_post.body
    assert_equal "anon", public_post.author_name
    assert_nil public_post.item_id
    assert_nil public_post.outfit_id
    assert_nil other_post.item_id
    assert_nil other_post.outfit_id
    assert Comment.exists?(preserved_comment.id), "public discussion was removed with the account"
    refute Comment.exists?(private_item_comment.id), "comment on deleted private item was left dangling"
    refute Comment.exists?(private_outfit_comment.id), "comment on deleted private outfit was left dangling"
    refute Shared::Reaction.exists?(private_comment_reaction.id), "reaction retained a deleted private comment"
    refute Shared::Notification.exists?(private_comment_notification.id), "notification retained a deleted private comment"
    refute Vote.exists?(private_comment_vote.id), "vote retained a deleted private comment"
    refute Shared::ReviewCase.exists?(item_review.id), "review case retained a deleted item target"
    refute Shared::ReviewCase.exists?(outfit_review.id), "review case retained a deleted outfit target"
    refute Shared::ReviewCase.exists?(reporter_review.id), "a report authored by the erased user survived"
    assert_nil Shared::ReviewCase.find(retained_review.id).reviewer_id,
               "reviewer identity must be removed while another person's audit is retained"
  end

  test "accounts outside the deletion grace period are untouched" do
    original_email = @user.email_address
    original_post = Post.create!(user: @user, body: "Keep this post")
    scheduled_at = 1.day.from_now
    @user.update_columns(deleted_at: Time.current, deletion_scheduled_at: scheduled_at)

    UserPurgeJob.perform_now

    assert_equal original_email, @user.reload.email_address
    assert_equal "Keep this post", original_post.reload.body
    assert_in_delta scheduled_at.to_f, @user.deletion_scheduled_at.to_f, 1
  end

  test "one failed erasure does not prevent other due accounts from being purged" do
    failed = @user
    completed = @other
    [ failed, completed ].each do |user|
      user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 1.second.ago)
    end
    job = UserPurgeJob.new
    erase = job.method(:erase!)
    job.define_singleton_method(:erase!) do |user|
      raise "synthetic erasure failure" if user.id == failed.id

      erase.call(user)
    end

    assert_raises(RuntimeError) { job.perform }

    assert_equal "purged-#{completed.id}@deleted.invalid", completed.reload.email_address
    assert_nil completed.deletion_scheduled_at
    assert failed.reload.deletion_scheduled_at.present?, "failed account must remain due for retry"
  end
end
