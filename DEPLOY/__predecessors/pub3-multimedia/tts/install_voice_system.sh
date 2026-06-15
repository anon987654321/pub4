#!/data/data/com.termux/files/usr/bin/bash
# Voice System Installation Script
# Reproduces complete Termux TTS setup with cultural voices

set -euo pipefail
echo "🎙️ Installing Termux Voice System..."
echo "=================================="

# Install required packages
echo "📦 Installing packages..."

pkg install -y python ruby sox play-audio termux-api

# Install Python TTS
echo "🐍 Installing gTTS..."

pip install gTTS

# Create cache directories
echo "📁 Creating cache directories..."

mkdir -p ~/.tts_cache_comfy

# Download core files (if URL provided, otherwise assumes files exist)
echo "📥 Core files should be present in current directory"

# Make all Ruby scripts executable
echo "🔧 Setting permissions..."

chmod +x *.rb 2>/dev/null || true

# Backup existing .bashrc
if [[ -f ~/.bashrc ]]; then

    echo "💾 Backing up .bashrc..."

    cp ~/.bashrc ~/.bashrc.backup.$(date +%s)

fi

# Add aliases to .bashrc
echo "⚙️ Configuring .bashrc..."

cat >> ~/.bashrc << 'EOF'

# Voice System Aliases
alias malay='ruby ~/malaysian_social.rb'

alias indian='ruby ~/indian_social.rb'

alias awkward='ruby ~/awkward_therapist.rb'

alias nervous='ruby ~/nervous_comfy.rb'

alias dirty='ruby ~/dirty_jokes.rb'

alias standup='ruby ~/standup_comedy.rb'

alias sarcastic='ruby ~/sarcastic_voice.rb'

alias brian='ruby ~/brian_tts.rb'

alias monologue='ruby ~/monologue_voice.rb'

alias therapist='ruby ~/therapist_voice.rb'

echo "🎙️ Voice system ready! Type 'malay' to start."
EOF

# Test installation
echo ""

echo "✅ Installation complete!"

echo ""

echo "📋 Available commands:"

echo "   malay      - Malaysian Manglish humor (DEFAULT)"

echo "   indian     - Indian desi humor"

echo "   awkward    - Awkward therapist"

echo "   nervous    - Insecure programmer"

echo "   dirty      - Adult jokes"

echo "   standup    - Comedy routine"

echo "   sarcastic  - Snarky voice"

echo "   brian      - Twitch donation voice"

echo ""

echo "🔊 Volume control:"

echo "   termux-volume music 12"

echo ""

echo "🛑 Stop all voices:"

echo "   pkill -9 ruby"

echo ""

echo "📖 Full documentation: ~/VOICE_SYSTEM_SETUP.md"

echo ""

echo "⚠️  For microphone support, install Termux:API from F-Droid:"

echo "   https://f-droid.org/packages/com.termux.api/"

echo ""

echo "🎉 Reload shell: source ~/.bashrc"

