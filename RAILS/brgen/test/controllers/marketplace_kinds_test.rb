# frozen_string_literal: true

require "test_helper"

# The non-goods half of a classifieds site. They are listings — same city
# scoping, same search, same expiry, same messaging — and they are not goods.
class MarketplaceKindsTest < ActionDispatch::IntegrationTest
  setup do
    # Once, not per test: sync! rewrites every city row, and under parallel
    # test workers two processes doing that into one SQLite file deadlock it
    # (SQLite3::BusyException). The guard makes setup a read in the steady
    # state.
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @lister = create_user("mk_lister")
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Diverse", slug: "diverse-#{SecureRandom.hex(4)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  def create_listing(kind, detail_key = nil, detail = {})
    params = { listing: { title: "#{kind} #{SecureRandom.hex(2)}", kind: kind, category_id: @category.id } }
    params[:listing][:price_cents] = 10_000 if kind == "goods"
    params[:listing]["#{detail_key}_attributes"] = detail if detail_key
    post marketplace.listings_path, params: params
    # id, not created_at: two listings created inside one second tie on the
    # timestamp, and .last under a tied sort handed back whichever row the
    # database felt like — the goods variable was sometimes the job record.
    Marketplace::Listing.order(:id).last
  end

  # A job advert has no price, and a form that demands one is a form people fill
  # in with noughts.
  test "a job needs no price and keeps its own facts" do
    sign_in_as(@lister)

    listing = create_listing("job", :job_detail, { employer: "Bergen Kommune", employment_type: "full_time",
                                                   salary_min_cents: 45_000_00, salary_max_cents: 55_000_00 })
    assert_equal "job", listing.kind
    assert_nil listing.price_cents
    assert_equal "Bergen Kommune", listing.job_detail.employer
    # Built from the same formatter rather than typed: MoneyDisplay joins with a
    # non-breaking space, and a literal here would assert the glyph.
    expected = "#{Shared::MoneyDisplay.format(45_000_00)}–#{Shared::MoneyDisplay.format(55_000_00)}"
    assert_equal expected, listing.headline_amount
  end

  # Rent is what people search on, so a housing advert without it is a phone
  # call — which is the thing a listing exists to replace.
  test "housing must state its rent" do
    sign_in_as(@lister)

    create_listing("housing", :housing_detail, { rooms: 2 })
    assert_response :unprocessable_entity

    listing = create_listing("housing", :housing_detail, { rent_cents: 12_000_00, rooms: 2, housing_type: "flat" })
    assert_equal "housing", listing.kind
    assert_equal Shared::MoneyDisplay.format(12_000_00), listing.headline_amount
  end

  test "a gig in the past is not an offer" do
    sign_in_as(@lister)

    create_listing("gig", :gig_detail, { pay_cents: 1_500_00, starts_at: 2.days.ago })
    assert_response :unprocessable_entity

    listing = create_listing("gig", :gig_detail, { pay_cents: 1_500_00, starts_at: 2.days.from_now, hours: 6 })
    assert_equal "gig", listing.kind
    assert_equal Shared::MoneyDisplay.format(1_500_00), listing.headline_amount
  end

  # Permitting all three detail blocks would let a job advert arrive carrying
  # rent, and the row would sit there with nothing rendering it.
  test "a listing carries only the details of its own kind" do
    sign_in_as(@lister)

    post marketplace.listings_path, params: {
      listing: { title: "Smuglet #{SecureRandom.hex(2)}", kind: "job", category_id: @category.id,
                 job_detail_attributes: { employer: "Ekte" },
                 housing_detail_attributes: { rent_cents: 999_00 } }
    }
    listing = Marketplace::Listing.order(:created_at).last
    assert_equal "Ekte", listing.job_detail.employer
    assert_nil listing.housing_detail
  end

  # A bicycle search should not turn up a job.
  test "the index shows one kind at a time, goods unless asked" do
    # A different lister for each: two_factor_required? turns on once an
    # account has an active listing, so the same user listing twice is asked for
    # a second factor rather than a second listing.
    sign_in_as(@lister)
    goods = create_listing("goods")
    sign_in_as(create_user("mk_second"))
    job = create_listing("job", :job_detail, { employer: "Kommunen" })

    get marketplace.listings_path
    assert_includes response.body, goods.title
    assert_not_includes response.body, job.title

    get marketplace.listings_path(kind: "job")
    assert_includes response.body, job.title
    assert_not_includes response.body, goods.title
  end

# two_factor_required? turns on the moment an account has an active listing, so
# the second listing is the first request the guard ever refuses — and from
# inside the engine the bare helper resolved against the engine's routes and
# raised UrlGenerationError. Every seller's second listing was a 500.
test "a seller listing again is sent to the host two-factor page, not a 500" do
  sign_in_as(@lister)
  create_listing("goods")

  get marketplace.new_listing_path
  assert_redirected_to "/two_factor_setup"
end

  test "the new-listing form asks for the fields of the kind it is on" do
    sign_in_as(@lister)

    get marketplace.new_listing_path(kind: "housing")
    assert_response :success
    assert_includes response.body, "listing[housing_detail_attributes][rent_cents]"
    assert_not_includes response.body, "listing[job_detail_attributes]"
  end

  # A salary range that runs backwards reads as a typo nobody can act on.
  test "a backwards salary range is refused" do
    detail = Marketplace::JobDetail.new(salary_min_cents: 60_000_00, salary_max_cents: 40_000_00)
    assert_not detail.valid?
    assert_includes detail.errors.attribute_names, :salary_max_cents
  end
end
