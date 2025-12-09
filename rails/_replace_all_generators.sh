#!/usr/bin/env zsh
set -euo pipefail

cd "G:/pub/rails"

echo "Replacing all generator files with pub2 complete versions..."

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen.sh -o brgen.sh
echo "✓ brgen.sh (15KB - Multi-tenant + acts_as_tenant + anonymous posting)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen_marketplace.sh -o brgen_marketplace.sh
echo "✓ brgen_marketplace.sh (17KB - Solidus e-commerce)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen_dating.sh -o brgen_dating.sh
echo "✓ brgen_dating.sh (28KB - Matchmaking service)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen_playlist.sh -o brgen_playlist.sh
echo "✓ brgen_playlist.sh (35KB - Music + Radio Bergen visualizer)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen_tv.sh -o brgen_tv.sh
echo "✓ brgen_tv.sh (42KB - Video streaming)"

curl -fsSL https://raw.githubusercontent.com/anon987654321/pub2/main/rails/brgen_takeaway.sh -o brgen_takeaway.sh
echo "✓ brgen_takeaway.sh (37KB - Food delivery)"

echo ""
echo "All generators replaced! Total: 174KB of complete implementations"
echo ""
echo "Features included:"
echo "  • Multi-tenancy with acts_as_tenant"
echo "  • Anonymous posting (guest_user_allowed?)"
echo "  • Infinite scroll with StimulusReflex"
echo "  • Mapbox integration"
echo "  • Live search"
echo "  • Rails 8 + Turbo + Stimulus"
echo "  • Complete CRUD with views"
echo "  • Faker seed data"
echo ""
echo "Next: Run syntax check"
echo "  zsh -n brgen.sh && echo 'brgen.sh: OK'"
echo "  zsh -n brgen_marketplace.sh && echo 'marketplace: OK'"
echo "  zsh -n brgen_dating.sh && echo 'dating: OK'"
echo "  zsh -n brgen_playlist.sh && echo 'playlist: OK'"
echo "  zsh -n brgen_tv.sh && echo 'tv: OK'"
echo "  zsh -n brgen_takeaway.sh && echo 'takeaway: OK'"
