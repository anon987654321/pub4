# frozen_string_literal: true

require "test_helper"

# Post had has_many :mentions and Notification::KINDS already ranked mention
# first, but nothing wrote a row, so an @name in a post reached nobody.
class MentionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "mn_author@brgen.no", password: "password123", username: "mn_author", city: @city
    )
    @named = User.strict_loading(false).create!(
      email_address: "mn_named@brgen.no", password: "password123", username: "mn_named", city: @city
    )
    @other = User.strict_loading(false).create!(
      email_address: "mn_other@brgen.no", password: "password123", username: "mn_other", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def post_with(content:, title: "Bryggen #{SecureRandom.hex(3)}")
    Post.create!(user: @author, title: title, content: content)
  end

  test "an at-name in the body writes a mention and notifies that user" do
    post = nil
    assert_difference -> { Mention.count }, 1 do
      assert_difference -> { @named.notifications.count }, 1 do
        post = post_with(content: "Hei @mn_named, noe skjer på Bryggen")
      end
    end

    assert_equal [ @named.id ], post.mentions.map(&:mentioned_user_id)
    notification = @named.notifications.last
    assert_equal "mention", notification.kind
    assert_equal @author, notification.actor
    assert_equal post, notification.notifiable
    assert_equal I18n.t("notifications.sentences.mention", name: @author.display_name), notification.title
  end

  test "an at-name in the title is enough" do
    post = post_with(title: "Til @mn_named #{SecureRandom.hex(3)}", content: "Noe skjer på Bryggen")

    assert_equal [ @named.id ], post.mentions.map(&:mentioned_user_id)
  end

  test "mentioning yourself writes nothing" do
    assert_no_difference -> { Mention.count } do
      assert_no_difference -> { @author.notifications.count } do
        post_with(content: "Jeg er @mn_author")
      end
    end
  end

  test "an unknown handle writes nothing" do
    assert_no_difference -> { Mention.count } do
      post_with(content: "Hei @finnes_ikke")
    end
  end

  test "an email address is not a mention" do
    User.strict_loading(false).create!(
      email_address: "mn_brgen@brgen.no", password: "password123", username: "brgen", city: @city
    )

    post = post_with(content: "Skriv til person@brgen.no")
    assert_empty post.mentions
  end

  test "the same handle twice is one row" do
    post = post_with(content: "Hei @mn_named og igjen @mn_named")
    assert_equal 1, post.mentions.count
  end

  test "two people each get a row and a notification" do
    post = post_with(content: "Hei @mn_named og @mn_other")

    assert_equal [ @named.id, @other.id ].sort, post.mentions.map(&:mentioned_user_id).sort
    assert_equal 1, @named.notifications.where(kind: "mention").count
    assert_equal 1, @other.notifications.where(kind: "mention").count
  end

  test "editing away a mention drops the join and does not notify again" do
    post = post_with(content: "Hei @mn_named")
    assert_equal 1, @named.notifications.where(kind: "mention").count

    assert_difference -> { post.mentions.count }, -1 do
      assert_no_difference -> { @named.notifications.count } do
        post.update!(content: "Ingen nevnt")
      end
    end
  end

  test "an unchanged mention on edit does not notify again" do
    post = post_with(content: "Hei @mn_named")

    assert_no_difference -> { Mention.count } do
      assert_no_difference -> { @named.notifications.count } do
        post.update!(content: "Hei igjen @mn_named")
      end
    end
  end

  test "a handle matches regardless of case" do
    post = post_with(content: "Hei @MN_Named")
    assert_equal [ @named.id ], post.mentions.map(&:mentioned_user_id)
  end

  test "destroying a post takes its mentions with it" do
    post = post_with(content: "Hei @mn_named")

    assert_difference -> { Mention.count }, -1 do
      post.destroy
    end
  end
end
