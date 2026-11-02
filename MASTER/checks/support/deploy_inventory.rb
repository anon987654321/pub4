# frozen_string_literal: true

# Deploy::Inventory has one implementation under OPENBSD/lib. MASTER checks
# use this path as a compatibility seam; keeping the definition here as well
# would let app inventory behavior drift between the scanner and deploy tools.
require_relative "../../../OPENBSD/lib/deploy_inventory"
