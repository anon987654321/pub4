#!/usr/bin/env zsh
# Rename shared modules to feature-based names
# Master.yml v70.0.0 reorganization

cd "$(dirname "$0")"

# Rename feature modules
mv @social_features.sh @features_voting_comments.sh 2>/dev/null || echo "Already renamed: @features_voting_comments.sh"
mv @chat_features.sh @features_messaging_realtime.sh 2>/dev/null || echo "Already renamed: @features_messaging_realtime.sh"
mv @marketplace_features.sh @features_booking_marketplace.sh 2>/dev/null || echo "Already renamed: @features_booking_marketplace.sh"
mv @ai_features.sh @features_ai_langchain.sh 2>/dev/null || echo "Already renamed: @features_ai_langchain.sh"

# Rename frontend modules
mv @stimulus_controllers.sh @frontend_stimulus.sh 2>/dev/null || echo "Already renamed: @frontend_stimulus.sh"
mv @reflex_patterns.sh @frontend_reflex.sh 2>/dev/null || echo "Already renamed: @frontend_reflex.sh"
mv @pwa_setup.sh @frontend_pwa.sh 2>/dev/null || echo "Already renamed: @frontend_pwa.sh"

# Rename generator modules
mv @view_generators.sh @generators_crud_views.sh 2>/dev/null || echo "Already renamed: @generators_crud_views.sh"

# Rename integration modules
mv @live_search.sh @integrations_search.sh 2>/dev/null || echo "Already renamed: @integrations_search.sh"
mv @live_chat.sh @integrations_chat_actioncable.sh 2>/dev/null || echo "Already renamed: @integrations_chat_actioncable.sh"

echo ""
echo "✓ Rename complete!"
echo "Run: ls @*.sh to verify"
