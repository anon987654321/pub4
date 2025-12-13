@echo off
REM Rename shared modules for clarity - Option A
REM Generated: 2025-12-13 04:17 UTC

echo Renaming shared modules to descriptive names...
echo.

ren @social_features.sh @votable_commentable.sh
echo ✓ @social_features.sh → @votable_commentable.sh

ren @live_chat.sh @actioncable_chat.sh
echo ✓ @live_chat.sh → @actioncable_chat.sh

ren @live_search.sh @debounced_search.sh
echo ✓ @live_search.sh → @debounced_search.sh

ren @chat_features.sh @messenger_conversations.sh
echo ✓ @chat_features.sh → @messenger_conversations.sh

ren @marketplace_features.sh @booking_reviews_payments.sh
echo ✓ @marketplace_features.sh → @booking_reviews_payments.sh

ren @ai_features.sh @langchain_completion.sh
echo ✓ @ai_features.sh → @langchain_completion.sh

ren @common.sh @shared_functions.sh
echo ✓ @common.sh → @shared_functions.sh

echo.
echo Rename complete! Now updating source statements in app generators...
echo.

dir @*.sh /b
