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
    outfit = Outfit.create!(user: @user, name: "Private occasion outfit")
    outfit.image.attach(io: StringIO.new("outfit-image"), filename: "outfit.jpg", content_type: "image/jpeg")

    item_blob_ids = item.photos.map(&:blob_id)
    profile_blob_ids = [profile.avatar.blob_id]
    outfit_blob_ids = [outfit.image.blob_id]

    public_post = Post.create!(user: @user, body: "Public outfit post", item: item, outfit: outfit)
    other_post = Post.create!(user: @other, body: "A post using the shared item", item: item, outfit: outfit)
    preserved_comment = Comment.create!(user: @user, commentable: other_post, content: "A public comment")
    private_item_comment = Comment.create!(user: @other, commentable: item, content: "Comment on private item")
    private_outfit_comment = Comment.create!(user: @other, commentable: outfit, content: "Comment on private outfit")

    provider_identity = ExternalIdentity.create!(
      user: @user, identity_provider: @provider, subject: "subject-#{@suffix}",
      email_address: @user.email_address, assurance_level: "verified"
    )
    merge_as_destination = AccountMerge.create!(guest_user: @other, user: @user, status: "merged", merged_at: Time.current)
    merge_as_guest = AccountMerge.create!(guest_user: @user, user: @other, status: "merged", merged_at: Time.current)
    session = @user.sessions.create!(user_agent: "private browser", ip_address: "192.0.2.44")

    sent = Message.create!(sender: @user, recipient: @other, body: "Private message sent")
    received = Message.create!(sender: @other, recipient: @user, body: "Private message received")
    Follow.create!(follower: @user, followee: @other)
    Follow.create!(follower: @other, followee: @user)
    Connection.create!(requester: @user, addressee: @other, status: "accepted")
    Shared::Reaction.create!(user: @user, reactable: item, kind: "like")
    Shared::Notification.create!(user: @user, actor: @other, kind: "alert")
    Shared::Notification.create!(user: @other, actor: @user, kind: "follow")

    other_creator = CreatorProfile.create!(
      user: @other, handle: "creator-#{@suffix}", display_name: "Other creator", public: true
    )
    creator_entry = CreatorWardrobeItem.create!(creator_profile: other_creator, item: item, caption: "Shared item")
    other_recommendation = Recommendation.create!(user: @other, item: item, kind: "declutter", reason: "A recommendation")
    other_challenge = DeclutterChallenge.create!(
      user: @other, item: Item.create!(user: @other, title: "Other garment", category: "Tops"),
      outfit: outfit, due_on: Date.current, status: "pending"
    )

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
    refute Session.exists?(id: session.id)

    assert_not Profile.exists?(profile.id), "profile survived erasure"
    assert_not Item.exists?(item.id), "private item survived erasure"
    assert_not Outfit.exists?(outfit.id), "private outfit survived erasure"
    assert_not WardrobeItem.exists?(wardrobe_item.id), "wardrobe record survived erasure"
    assert_not ExternalIdentity.exists?(provider_identity.id), "provider subject survived erasure"
    assert_not AccountMerge.exists?(merge_as_destination.id), "merge audit by destination survived erasure"
    assert_not AccountMerge.exists?(merge_as_guest.id), "merge audit by guest survived erasure"
    assert_not CreatorWardrobeItem.exists?(creator_entry.id), "creator reference to private item survived erasure"
    assert_not Recommendation.exists?(other_recommendation.id), "recommendation leaked a private item"
    assert_nil other_challenge.reload.outfit_id, "another account's challenge retained the deleted outfit id"
    assert_empty Message.where(id: [sent.id, received.id]), "private inbox messages survived erasure"
    assert_empty Follow.where("follower_id = :id OR followee_id = :id", id: @user.id)
    assert_empty Connection.where("requester_id = :id OR addressee_id = :id", id: @user.id)
    assert_empty Shared::Reaction.where(user_id: @user.id)
    assert_empty Shared::Notification.where("user_id = :id OR actor_id = :id", id: @user.id)

    [*profile_blob_ids, *item_blob_ids, *outfit_blob_ids].each do |blob_id|
      assert_empty ActiveStorage::Attachment.where(blob_id: blob_id), "an erased user's attachment survived"
    end

    public_post.reload
    other_post.reload
    assert_equal "Public outfit post", public_post.body
    assert_equal "anon", public_post.author_name
    assert_nil public_post.item_id
    assert_nil public_post.outfit_id
    assert_nil other_post.item_id
    assert_nil other_post.outfit_id
    assert Comment.exists?(preserved_comment.id), "public discussion was removed with the account"
    refute Comment.exists?(private_item_comment.id), "comment on deleted private item was left dangling"
    refute Comment.exists?(private_outfit_comment.id), "comment on deleted private outfit was left dangling"
  end

  test "accounts outside the deletion grace period are untouched" do
    original_email = @user.email_address
    original_post = Post.create!(user: @user, body: "Keep this post")
    @user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 1.day.from_now)

    UserPurgeJob.perform_now

    assert_equal original_email, @user.reload.email_address
    assert_equal "Keep this post", original_post.reload.body
    assert_equal 1.day.from_now.to_date, @user.deletion_scheduled_at.to_date
  end
end
