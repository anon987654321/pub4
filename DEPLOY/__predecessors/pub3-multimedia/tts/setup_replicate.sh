#!/data/data/com.termux/files/usr/bin/bash
echo "🎙️ Replicate AI Voice Setup"
echo "============================="

echo ""

echo "To use premium AI voices from Replicate:"

echo ""

echo "1. Sign up at: https://replicate.com"

echo "2. Go to Account Settings → API Tokens"

echo "3. Copy your API token"

echo ""

echo "4. Set your token:"

echo "   export REPLICATE_API_TOKEN='r8_your_token_here'"

echo ""

echo "5. Make it permanent (add to ~/.bashrc):"

echo "   echo \"export REPLICATE_API_TOKEN='r8_your_token_here'\" >> ~/.bashrc"

echo ""

echo "6. Run the voice:"

echo "   ruby ~/replicate_voice.rb"

echo ""

echo "Available Premium Models:"

echo "  - XTTS-V2: Voice cloning, 12+ languages"

echo "  - Kokoro-82M: Lightweight, high quality"

echo "  - F5-TTS: Excellent synthesis quality"

echo ""

echo "Without API token, script falls back to gTTS."

echo ""

