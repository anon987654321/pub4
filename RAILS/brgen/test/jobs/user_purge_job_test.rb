# frozen_string_literal: true

require "test_helper"

# The users row is anonymised rather than destroyed, so nothing in the graph
# cascades and every table holding personal data has to be reached by name.
# This builds an account that has data in each of them and asserts, one row at
# a time, that erasure got there. Every assertion here fails against the job as
# it stood before: it touched the users row and its sessions and nothing else.
class UserPurgeJobTest < ActiveJob::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "erase-me@brgen.no", password: "password123", city: @city,
      latitude: 60.39, longitude: 5.32
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def purge!
    @user.update_columns(
      deleted_at: Time.current,
      deletion_scheduled_at: 1.day.ago,
      email_verification_token: "verification-token",
      magic_link_token: "magic-token",
      magic_link_expires_at: 1.hour.from_now
    )
    UserPurgeJob.perform_now
  end

  test "social relationship rows are erased" do
    ActsAsTenant.with_tenant(@city) do
      other = User.create!(
        email_address: "relation-other-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123",
        city: @city
      )
      post = Post.create!(user: other, title: "Relationship target", content: "x", city: @city)
      listing = Marketplace::Listing.create!(
        user: other,
        title: "Saved listing",
        price_cents: 100,
        status: "active"
      )
      community = Community.create!(
        name: "Relation #{SecureRandom.hex(3)}",
        user: other,
        city: @city
      )

      Follow.create!(follower: @user, followed: other)
      Block.create!(blocker: other, blocked: @user)
      Bookmark.create!(user: @user, post: post)
      Marketplace::ListingFavorite.create!(user: @user, listing: listing)
      CommunityMembership.create!(user: @user, community: community, role: "member")
      Dating::Like.create!(liker: @user, likee: other)
      Dating::Dislike.create!(disliker: other, dislikee: @user)

      purge!

      assert_empty Follow.where("follower_id = :id OR followed_id = :id", id: @user.id)
      assert_empty Block.where("blocker_id = :id OR blocked_id = :id", id: @user.id)
      assert_empty Bookmark.where(user_id: @user.id)
      assert_empty Marketplace::ListingFavorite.where(user_id: @user.id)
      assert_empty CommunityMembership.where(user_id: @user.id)
      assert_empty Dating::Like.where("liker_id = :id OR likee_id = :id", id: @user.id)
      assert_empty Dating::Dislike.where("disliker_id = :id OR dislikee_id = :id", id: @user.id)
    end
  end

  test "private account relations are erased" do
    ActsAsTenant.with_tenant(@city) do
      other = User.create!(
        email_address: "purge-other-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123",
        city: @city
      )
      conversation = Conversation.create!(conversation_type: "direct")
      ConversationParticipant.create!(conversation: conversation, user: @user)
      message = Message.create!(conversation: conversation, sender: @user, content: "private", message_type: "text")

      notification = Notification.create!(user: @user, kind: "alert")
      assurance = IdentityAssurance.create!(user: @user, level: "account", source: "test")
      reputation = ReputationScore.create!(user: @user, scope: "global")
      trust = TrustSignal.create!(user: @user, kind: "test", source: SecureRandom.uuid)
      receipt = MessageReceipt.create!(message: message, user: @user)
      typing = TypingIndicator.create!(conversation: conversation, user: @user, expires_at: 1.minute.from_now)
      merge = AccountMerge.create!(guest_user: other, user: @user, status: "merged")
      event = Event.create!(user: @user, title: "Private RSVP", starts_at: 2.days.from_now)
      rsvp = EventRsvp.create!(event: event, user: @user, status: "interested")
      story = Story.new(user: @user, city: @city, expires_at: 1.day.from_now)
      story.media.attach(io: StringIO.new("jpegbytes"), filename: "private-story.jpg", content_type: "image/jpeg")
      story.save!
      view = StoryView.create!(story: story, user: @user)

      purge!

      {
        notification: Notification.exists?(notification.id),
        assurance: IdentityAssurance.exists?(assurance.id),
        reputation: ReputationScore.exists?(reputation.id),
        trust: TrustSignal.exists?(trust.id),
        receipt: MessageReceipt.exists?(receipt.id),
        typing: TypingIndicator.exists?(typing.id),
        merge: AccountMerge.exists?(merge.id),
        rsvp: EventRsvp.exists?(rsvp.id),
        view: StoryView.exists?(view.id)
      }.each do |name, present|
        assert_not present, "#{name} survived account erasure"
      end
    end
  end

  test "the account itself is anonymised" do
    ActsAsTenant.with_tenant(@city) do
      purge!

      @user.reload
      assert_equal "purged-#{@user.id}@deleted.invalid", @user.email_address
      assert_nil @user.latitude
      assert_nil @user.longitude
      assert_nil @user.deletion_scheduled_at
      assert_nil @user.email_verification_token
      assert_nil @user.magic_link_token
      assert_nil @user.magic_link_expires_at
      assert_not_nil @user.deleted_at
    end
  end

  # The most sensitive rows in the tree: a bio, coordinates, profile
  # photographs, and a selfie taken to prove the person is who they say.
  test "the dating profile, its verifications and its photographs are gone" do
    ActsAsTenant.with_tenant(@city) do
      profile = Dating::Profile.create!(user: @user, bio: "Liker fjellturer", age: 34,
                                        gender: "man", looking_for: "woman",
                                        latitude: 60.39, longitude: 5.32, location: "Bergen")
      profile.photos.attach(io: StringIO.new("jpegbytes"), filename: "me.jpg", content_type: "image/jpeg")
      verification = Dating::Verification.new(profile: profile, pose: Dating::Verification.pose_for_request)
      verification.selfie.attach(io: StringIO.new("selfiebytes"), filename: "selfie.jpg", content_type: "image/jpeg")
      verification.save!

      assert profile.photos.attached?
      assert verification.selfie.attached?
      blob_ids = profile.photos.map(&:blob_id) + [ verification.selfie.blob_id ]

      purge!

      assert_empty Dating::Profile.where(user_id: @user.id), "the dating profile survived erasure"
      assert_empty Dating::Verification.where(id: verification.id), "the verification survived erasure"
      assert_empty ActiveStorage::Attachment.where(blob_id: blob_ids),
                   "photographs were left attached in storage"
    end
  end

  test "federation signing credentials are gone" do
    @user.update_columns(
      private_key: "PRIVATE-KEY",
      public_key: "PUBLIC-KEY"
    )

    purge!

    assert_nil @user.reload.private_key
    assert_nil @user.reload.public_key
  end

  test "federated follow relationships are gone" do
    actor = FediActor.create!(
      uri: "https://remote.example/users/purge-#{SecureRandom.hex(4)}",
      inbox_url: "https://remote.example/inbox"
    )
    FediFollow.create!(user: @user, fedi_actor: actor, state: "accepted", direction: "outbound")

    purge!

    assert_empty FediFollow.where(user_id: @user.id),
                 "federated follow relationships survived erasure"
  end

  test "push credentials are gone" do
    ActsAsTenant.with_tenant(@city) do
      PushSubscription.create!(
        user: @user,
        endpoint: "https://push.example/sub/#{SecureRandom.hex(8)}",
        p256dh: SecureRandom.hex(16),
        auth: SecureRandom.hex(8)
      )

      purge!

      assert_empty PushSubscription.where(user_id: @user.id),
                   "push credentials survived erasure"
    end
  end

  test "postal addresses and federated identities are gone" do
    ActsAsTenant.with_tenant(@city) do
      Marketplace::Address.create!(user: @user, recipient: "Johann", line1: "Storgata 1",
                                   postcode: "5003", city_name: "Bergen", phone: "+4790000000")
      provider = IdentityProvider.create!(name: "BankID", slug: "bankid-#{SecureRandom.hex(3)}")
      ExternalIdentity.create!(user: @user, identity_provider: provider, subject: SecureRandom.uuid,
                               email_address: "erase-me@bankid.no", phone_number: "+4790000000")

      purge!

      assert_empty Marketplace::Address.where(user_id: @user.id), "a postal address survived erasure"
      assert_empty ExternalIdentity.where(user_id: @user.id), "a federated identity survived erasure"
    end
  end

  # The order stays — it is a financial record the restaurant may be required
  # to keep — but where it was delivered is not part of that obligation.
  test "a takeaway order keeps its money and loses its address" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(name: "Pizzabakeren", city: @city, address: "Torget 2",
                                                cuisine_type: "Pizza", user: @user, active: true)
      item = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Margherita", price_cents: 24_900)
      order = Takeaway::Order.new(user: @user, restaurant: restaurant, status: "pending",
                                  delivery_address: "Storgata 1, 5003 Bergen",
                                  special_instructions: "Ring på nabodøra", total_cents: 24_900)
      order.order_items.build(menu_item: item, quantity: 1, unit_price_cents: 24_900, user: @user)
      order.save!

      purge!

      order.reload
      assert_nil order.delivery_address, "the delivery address survived erasure"
      assert_nil order.special_instructions
      assert_equal 24_900, order.total_cents, "the financial record must be retained"
    end
  end

  # Content is kept so threads do not collapse, but the coordinates recorded
  # when it was written say where the person was standing.
  test "posts and stories keep their text and lose their coordinates" do
    ActsAsTenant.with_tenant(@city) do
      post = Post.create!(user: @user, title: "Sol på Fløyen", city: @city,
                          latitude: 60.39, longitude: 5.32)
      story = Story.new(user: @user, city: @city, expires_at: 1.day.from_now,
                        latitude: 60.39, longitude: 5.32)
      story.media.attach(io: StringIO.new("jpegbytes"), filename: "s.jpg", content_type: "image/jpeg")
      story.save!

      purge!

      assert_equal "Sol på Fløyen", post.reload.title, "content must survive erasure"
      assert_nil post.latitude, "a post kept the coordinates it was written at"
      assert_nil story.reload.latitude, "a story kept the coordinates it was written at"
    end
  end

  # Keyed by address rather than by user_id, so it can only be found before the
  # address is overwritten.
  test "the newsletter subscription goes with the address it was made under" do
    ActsAsTenant.with_tenant(@city) do
      EmailSubscription.create!(email: "erase-me@brgen.no", token: SecureRandom.hex(8),
                                city: "Bergen", confirmed: true)

      purge!

      assert_empty EmailSubscription.where(email: "erase-me@brgen.no"),
                   "the subscription outlived the account that made it"
    end
  end

  # The other half of RAILS/test/erasure_coverage_test.rb. That file asserts
  # every table with personal columns has a disposition recorded; this asserts
  # the recorded disposition is the one the job actually performs, by asking
  # each model for its table_name rather than pluralising its constant. The
  # first draft of the coverage test guessed instead, produced
  # "marketplace_addresss", matched nothing, and passed.
  # RAILS/test/ is not inside this app, and on the box it is not beside it either.
  # Rails.root is /home/brgen/app there, so Rails.root/.. is /home/brgen — a real
  # directory with no test/ in it, which is why `require Rails.root.join("../test/
  # erasure_coverage_test")` resolved in a source checkout and raised LoadError on
  # "/home/brgen/test/erasure_coverage_test" on every VPS deploy. It failed the
  # whole Rails suite at 0 failures, 1 error and halted the pass.
  #
  # Same candidate order as test/source_reader.rb, whose comment records why the
  # canonical checkout comes before the per-app pub4-rails copy: those copies go
  # stale without anything noticing.
  ERASURE_COVERAGE_ROOTS = [
    ENV["PUB4_RAILS_ROOT"],
    "/home/dev/pub4/RAILS",
    "/home/#{ENV.fetch('PUB4_CI_APP', 'brgen')}/pub4-rails/RAILS",
    File.expand_path("../../..", __dir__)
  ].compact.freeze

  test "every table the job touches is classified the way the job treats it" do
    found = ERASURE_COVERAGE_ROOTS
            .map { |root| File.join(root, "test", "erasure_coverage_test.rb") }
            .find { |path| File.readable?(path) }
    # Not a skip: this test exists to catch a table the job touches and nothing
    # classifies, and a silent skip is exactly how that gap would survive. Name
    # what was searched so the next reader fixes the sync rather than the test.
    assert found, "erasure_coverage_test.rb not readable under any of: #{ERASURE_COVERAGE_ROOTS.join(', ')}"
    require found
    classified = ErasureCoverageTest::CLASSIFIED

    { destroy: UserPurgeJob::DESTROY, nullify: UserPurgeJob::NULLIFY }.each do |disposition, rows|
      rows.each do |row|
        model = row[:model].safe_constantize
        assert model, "#{row[:model]} does not resolve — the job must fail closed and retry later"

        recorded = classified[model.table_name]
        assert recorded, "#{model.table_name} is touched by the job and classified nowhere"
        assert_equal disposition, recorded.first,
                     "#{model.table_name} is classified #{recorded.first} but the job #{disposition}s it"

        Array(row[:columns]).each do |column|
          assert_includes model.column_names, column.to_s,
                          "#{model.table_name}.#{column} does not exist — the job nullifies nothing"
        end
      end
    end
  end

  test "a missing erasure dependency leaves the account queued for retry" do
    ActsAsTenant.with_tenant(@city) do
      @user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 1.day.ago)
      job = UserPurgeJob.new
      job.define_singleton_method(:resolve!) { |_name| raise "simulated missing table" }

      assert_raises(RuntimeError) { job.send(:erase!, @user) }
      assert_equal 1.day.ago.to_date, @user.reload.deletion_scheduled_at.to_date,
                   "a failed erasure must remain eligible for the next purge run"
    end
  end

  test "erasure runs as one database transaction" do
    ActsAsTenant.with_tenant(@city) do
      transactional = false
      job = UserPurgeJob.new
      original = job.method(:anonymise)
      job.define_singleton_method(:anonymise) do |user|
        transactional = ActiveRecord::Base.connection.transaction_open?
        original.call(user)
      end

      job.send(:erase!, @user)

      assert transactional, "all erasure changes must share one database transaction"
    end
  end

  test "an account still inside its grace window is not touched" do
    ActsAsTenant.with_tenant(@city) do
      profile = Dating::Profile.create!(user: @user, bio: "Still here", age: 30)
      @user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 29.days.from_now)

      UserPurgeJob.perform_now

      assert Dating::Profile.exists?(profile.id), "erasure ran before the grace window closed"
      assert_equal "erase-me@brgen.no", @user.reload.email_address
    end
  end
end
