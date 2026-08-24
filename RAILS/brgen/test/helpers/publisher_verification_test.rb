# frozen_string_literal: true

require "test_helper"

# TradeDoubler's local publisher team verifies site ownership by loading a page
# that displays the account's Site ID, alongside a visible contact email and a
# reachable cookie policy (support thread, 2026-08-07). Those three things are
# an external dependency on our markup: if a refactor drops them, nothing else
# in the suite notices and the next verification attempt fails for a reason no
# gate reports.
class PublisherVerificationTest < ActionDispatch::IntegrationTest
  # brgen routes through Brgen::DomainRegistry, so an integration request with
  # no host is "Unknown host", not the front page.
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "privacy terms and cookies are public" do
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, "legal-prose"
    end
  end

  test "the site id and contact email render on the front page for a signed-out visitor" do
    with_env("TRADEDOUBLER_SITE_ID" => "24680", "SITE_CONTACT_EMAIL" => "verify@example.test") do
      get root_path

      assert_response :success
      assert_select "footer.site-legal" do
        assert_select ".site-verify-id strong", text: "24680",
                      body: "the publisher team reads the Site ID off this page while signed out"
        assert_select ".site-verify-contact a[href=?]", "mailto:verify@example.test"
      end
    end
  end

  # The token is issued after approval; this block is what gets you approved.
  # Gating it on the token would hide it for exactly as long as it is needed.
  test "the site id does not depend on TRADEDOUBLER_TOKEN being present" do
    with_env("TRADEDOUBLER_SITE_ID" => "24680", "TRADEDOUBLER_TOKEN" => nil) do
      get root_path

      assert_select ".site-verify-id strong", text: "24680"
    end
  end

  test "an unconfigured site renders no empty labels" do
    with_env("TRADEDOUBLER_SITE_ID" => nil, "SITE_CONTACT_EMAIL" => nil) do
      get root_path

      assert_response :success
      assert_select ".site-verify", 0
    end
  end

  # "Your site should also have a GDPR cookie policy visible."
  test "the cookie policy is linked from the footer and loads for a signed-out visitor" do
    get root_path

    assert_response :success
    assert_select "footer.site-legal nav a[href=?]", cookies_path

    get cookies_path

    assert_response :success
    assert_select "h1"
  end
end
