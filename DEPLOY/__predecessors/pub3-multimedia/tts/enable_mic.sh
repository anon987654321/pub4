#!/data/data/com.termux/files/usr/bin/bash
echo "🎤 Enabling microphone..."
# Test microphone access
echo "🎤 Testing microphone permissions..."

termux-microphone-record -l 2 -f /tmp/mic_test.wav -e opus -b 128 -r 44100 -c 1

sleep 3
echo "🎤 Stopping test recording..."
termux-microphone-record -q

if [ -f /tmp/mic_test.wav ]; then
    echo "✅ Microphone enabled successfully!"

    echo "📊 Test recording saved to: /tmp/mic_test.wav"

    ls -lh /tmp/mic_test.wav

    rm /tmp/mic_test.wav

else

    echo "❌ Failed to enable microphone. Please check permissions in Android settings."

fi

echo ""
echo "🎤 Microphone is now ready for use!"

echo "   Use: termux-microphone-record -f output.wav -l <seconds>"

