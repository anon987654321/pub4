# frozen_string_literal: true

# Fetch a page of items matching the given criteria.
# Ensures deterministic ordering and prevents potential SQL injection.
results =
  Item
    .where(criteria)
    .order(:id)                     # deterministic order
    .limit(page_size)
    .offset(page * page_size)       # paginate safely
