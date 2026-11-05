# frozen_string_literal: true

require "test_helper"

# A profile with more posts than a page keeps going: the first page ends in the
# infinite-scroll sentinel, with the pager for a reader without JavaScript,
# and the reflex behind the sentinel pages the profile's own scope.
class ProfilePostsPaginationTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    handle = "mange_#{SecureRandom.hex(3)}"
    @author = User.create!(email_address: "#{handle}@brgen.no", password: "password123", username: handle)
  end

  def posts(count, **attrs)
    count.times.map { |i| Post.create!(user: @author, city: @city, title: "Innlegg #{i}", content: "hei", **attrs) }
  end

  def reflex_scope
    reflex = ProfilePostsInfiniteScrollReflex.allocate
    author_id = @author.id.to_s
    reflex.define_singleton_method(:element) { Struct.new(:dataset).new({ "user_id" => author_id }) }
    reflex.send(:scope)
  end

  test "a profile past one page ends in the sentinel and a no-JS pager" do
    posts(27)

    get user_path(@author)

    assert_select "ul#profile-posts > li", 25
    assert_select "#profile-posts-sentinel[data-next-page='2'][data-user-id='#{@author.id}']" \
                  "[data-reflex='ProfilePostsInfiniteScrollReflex#load_more']"
    assert_select "noscript", 1
  end

  test "a profile that fits one page has no sentinel" do
    posts(3)

    get user_path(@author)

    assert_select "ul#profile-posts > li", 3
    assert_select "#profile-posts-sentinel", count: 0
  end

  test "the reflex pages the profile's own posts, newest first, without anonymous ones" do
    shown = posts(2)
    posts(1, anonymous: true)

    assert_equal shown.reverse.map(&:id), reflex_scope.pluck(:id)
  end
end
