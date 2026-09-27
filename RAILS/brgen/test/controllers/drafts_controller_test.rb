# frozen_string_literal: true

require "test_helper"

# Shared::DraftsActions, promoted out of the identical copies amber and brgen
# each carried. Nothing covered it in either app.
class DraftsControllerTest < ActionDispatch::IntegrationTest
  # brgen resolves city/branding from the host, and ApplicationController 404s
  # an unknown one — the default www.example.com is not a brgen domain.
  setup { host! "brgen.no" }

  def test_update_stores_the_form_body_in_the_session_under_its_id
    patch draft_path("post_new"), params: { title: "Half-written", body: "…" }

    assert_response :no_content
    draft = session[:drafts]["post_new"]
    assert_equal "Half-written", draft["title"]
    assert_equal "…", draft["body"]
  end

  # Rails' own routing/CSRF keys are not part of the user's draft; storing them
  # would round-trip a stale authenticity_token back into the form.
  def test_update_strips_rails_control_params
    patch draft_path("post_new"), params: { title: "x" }

    draft = session[:drafts]["post_new"]
    %w[controller action id authenticity_token _method].each do |key|
      refute draft.key?(key), "draft kept #{key}"
    end
  end

  def test_drafts_are_keyed_separately_per_form
    patch draft_path("post_new"), params: { title: "one" }
    patch draft_path("comment_9"), params: { title: "two" }

    assert_equal "one", session[:drafts]["post_new"]["title"]
    assert_equal "two", session[:drafts]["comment_9"]["title"]
  end
end


  def test_update_redacts_credential_shaped_fields
    patch draft_path("post_new"), params: {
      title: "Half-written",
      "user[password]": "super-secret",
      "oauth[token]": "bearer-secret"
    }

    assert_response :no_content
    draft = session[:drafts]["post_new"]
    assert_equal "Half-written", draft["title"]
    refute_includes draft.keys.map(&:to_s), "user[password]"
    refute_includes draft.keys.map(&:to_s), "oauth[token]"
  end

  def test_update_rejects_an_oversized_cookie_draft
    patch draft_path("post_new"), params: { body: "x" * (Shared::DraftsActions::MAX_BYTES + 1) }

    assert_response :content_too_large
    assert_nil session[:drafts]&.[]("post_new")
  end
