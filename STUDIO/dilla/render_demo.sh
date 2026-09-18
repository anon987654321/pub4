#!/bin/zsh
# Bare dilla invoke: renders the 16-piece catalogue through Bed into demo.wav/demo.mp3 beside dilla.rb.
cd /Users/mac/Documents/GitHub/pub4/STUDIO/dilla
/opt/homebrew/bin/ruby dilla.rb >> /Users/mac/Documents/GitHub/pub4/STUDIO/dilla/render.log 2>&1
echo "RENDER_EXIT=$?" >> /Users/mac/Documents/GitHub/pub4/STUDIO/dilla/render.log