# frozen_string_literal: true

# Public legal pages — GDPR + publisher review require them without an account.
# instance_eval from each app's config/routes.rb.

%w[privacy terms cookies].each do |legal_page|
  get legal_page, to: "pages#show", defaults: { page: legal_page }, as: legal_page
end
