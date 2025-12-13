@echo off
REM Remove duplicate shared modules per ANALYSIS_COMPLETE_2025-12-13.md

echo Removing duplicate shared modules...

del @langchain_features.sh
echo Removed @langchain_features.sh (duplicate of @ai_features.sh)

del @airbnb_features.sh
echo Removed @airbnb_features.sh (duplicate of @marketplace_features.sh)

del @messaging_features.sh
echo Removed @messaging_features.sh (duplicate of @chat_features.sh)

del @reddit_features.sh
echo Removed @reddit_features.sh (duplicate of @social_features.sh)

echo.
echo Duplication cleanup complete!
echo Saved ~2,010 lines of code.
echo.
dir @*.sh /b
