# frozen_string_literal: true

require "minitest/autorun"

# UserPurgeJob anonymises the users row rather than destroying it, so that
# threads keep their shape. The consequence is that no `dependent: :destroy`
# anywhere in the graph fires during erasure — nothing is destroyed, so nothing
# cascades — and every table holding personal data has to be named in the job
# by hand or it is simply kept.
#
# Which is how it went wrong. The job reached the users row and its sessions,
# and a purged account still had its dating profile with bio, coordinates,
# profile photographs and an identity-verification selfie; its postal addresses
# with recipient and phone; its federated email and phone number; its delivery
# addresses; its newsletter subscription; and the coordinates recorded on every
# post, story, listing and event it had made.
#
# A hand-maintained list goes stale the first time somebody adds a table, so
# this is the check that turns that into a failing test: every table in the
# schema carrying a personal-data column is classified below, with a reason.
# Adding a table and not deciding is the failure.
#
# The other half of the contract — that a table classified :destroy or :nullify
# is genuinely reached by the job — needs real models, so it lives in
# brgen/test/jobs/user_purge_job_test.rb where table_name can be asked rather
# than guessed. An earlier draft of this file guessed, by pluralising a
# constant name, and produced "marketplace_addresss" and
# "marketplace_saved_searchs" — matching nothing, while every table happened to
# be covered by the exemption list, so the broken half passed in silence.
class ErasureCoverageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCHEMA = File.join(ROOT, "brgen", "db", "schema.rb")

  # Column names that mean "this row says something about a person". Coarse on
  # purpose: a false positive costs one line here with a reason, and a false
  # negative is personal data kept after an erasure request.
  PERSONAL = /
    \A(bio|about|phone|phone_number|address|line1|line2|recipient|postcode
    |latitude|longitude|location|birth|dob|selfie|avatar|real_name|full_name
    |display_name|email|email_address|ip_address|user_agent|delivery_address
    |special_instructions)\z
  /x

  DISPOSITIONS = %i[destroy nullify handled not_personal].freeze

  # Every table whose columns look personal, and what erasure does about it.
  #
  #   :destroy      the job destroys the row (and its attachments with it)
  #   :nullify      the row is retained; the job clears the personal columns
  #   :handled      erasure reaches it some other way, named in the reason
  #   :not_personal the columns are not about one of our users
  CLASSIFIED = {
    "dating_profiles"            => [ :destroy, "the profile exists only to describe the person; photographs and the verification selfie go with it" ],
    "external_identities"        => [ :destroy, "a federated login carrying their email and phone number" ],
    "marketplace_addresses"      => [ :destroy, "recipient, street, postcode and phone, and nothing else" ],
    "marketplace_saved_searches" => [ :destroy, "what someone searched for, saved under their name" ],

    "takeaway_orders"       => [ :nullify, "retained as a financial record (Art. 17(3)(b)); the address it went to is not part of that" ],
    "posts"                 => [ :nullify, "content is retained so threads do not collapse; the coordinates it was written at are not" ],
    "stories"               => [ :nullify, "as posts: the story is retained, the coordinates it was posted from are not" ],
    "marketplace_listings"  => [ :nullify, "the listing is half of somebody else's order; where the goods are is usually where the seller lives" ],
    "marketplace_checkouts" => [ :nullify, "its address FK points at a row this job destroys" ],
    "events"                => [ :nullify, "a venue is not a home, but the coordinates on one somebody hosted are theirs" ],

    "users"               => [ :handled, "the account row itself, anonymised in place by anonymise" ],
    "sessions"            => [ :handled, "erase! calls user.sessions.delete_all" ],
    "email_subscriptions" => [ :handled, "keyed by address rather than user_id; erase_email_subscription reads the address before it is overwritten" ],

    "cities"                => [ :not_personal, "a city's own coordinates" ],
    "places"                => [ :not_personal, "a public place's address, with no owning user" ],
    "fedi_actors"           => [ :not_personal, "an actor on another server — not our account to erase" ],
    "takeaway_restaurants"  => [ :not_personal, "a business address, and the business is not the user" ],
  }.freeze

  def schema = @schema ||= File.read(SCHEMA)

  def tables_with_personal_columns
    schema.scan(/create_table "([^"]+)"/).flatten.filter_map do |table|
      body = schema[/create_table "#{Regexp.escape(table)}".*?\n  end\n/m].to_s
      columns = body.scan(/t\.\w+ "([^"]+)"/).flatten.select { |c| c.match?(PERSONAL) }
      [ table, columns ] if columns.any?
    end.to_h
  end

  def test_the_schema_is_where_this_test_looks
    assert File.exist?(SCHEMA), "schema.rb is not here — the check is wrong, not the tree"
    refute_empty tables_with_personal_columns,
                 "no personal columns found at all, which means PERSONAL matches nothing"
  end

  def test_every_table_with_personal_data_is_classified
    unclassified = tables_with_personal_columns.keys.reject { |t| CLASSIFIED.key?(t) }

    assert_empty unclassified, <<~MSG
      These tables carry personal-data columns and erasure has no decision
      recorded for them, so an Art. 17 request leaves their rows intact:

      #{unclassified.map { |t| "  #{t}: #{tables_with_personal_columns[t].join(', ')}" }.join("\n")}

      Add each to CLASSIFIED with one of #{DISPOSITIONS.join(', ')} and the
      reason — and for :destroy or :nullify, to UserPurgeJob as well.
    MSG
  end

  def test_every_classification_names_a_disposition_and_a_reason
    bad = CLASSIFIED.reject do |_, (disposition, reason)|
      DISPOSITIONS.include?(disposition) && reason.to_s.strip.length >= 20
    end.keys

    assert_empty bad, "a classification without a real disposition and reason is a silent decision: #{bad.join(', ')}"
  end

  # A classification for a table that no longer exists is a reason nobody will
  # read attached to nothing, and it hides the next table that needs one.
  def test_no_classification_outlives_its_table
    stale = CLASSIFIED.keys - schema.scan(/create_table "([^"]+)"/).flatten

    assert_empty stale, "CLASSIFIED names tables that are not in the schema: #{stale.join(', ')}"
  end
end
