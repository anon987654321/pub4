#!/usr/bin/env bash
# LoRA Masterpiece Workflow

# Full pipeline: Photos → LoRA → Upscale → Rembg → Animate → Music → Random Chains
set -euo pipefail

PHOTOS_DIR="$HOME/photos"

OUTPUT_DIR="$HOME/output"
REPLIGEN_DIR="$HOME/repligen"
MUSIC_FILE="$HOME/music.mp3"

echo "╔═══════════════════════════════════════════════════════════════╗"

echo "║         LORA MASTERPIECE WORKFLOW                            ║"

echo "║    Photos → LoRA → Upscale → Animate → Music → Chains       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

echo ""

# Check prerequisites

if [ ! -d "$PHOTOS_DIR" ] || [ -z "$(ls -A $PHOTOS_DIR 2>/dev/null)" ]; then

    echo "❌ No photos found in $PHOTOS_DIR"
    echo "Upload photos first:"

    echo "  scp /path/to/photos/* dev@185.52.176.18:~/photos/"

    exit 1

fi

if [ -z "${REPLICATE_API_TOKEN:-}" ]; then

    echo "❌ REPLICATE_API_TOKEN not set"

    echo "Set it with:"
    echo '  echo "export REPLICATE_API_TOKEN=your_token" >> ~/.profile'

    echo "  source ~/.profile"

    exit 1

fi

# Count photos

PHOTO_COUNT=$(ls -1 "$PHOTOS_DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG} 2>/dev/null | wc -l)

echo "📸 Found $PHOTO_COUNT photos in $PHOTOS_DIR"
if [ "$PHOTO_COUNT" -lt 5 ]; then

    echo "⚠️  Warning: LoRA training works best with 5+ photos"

fi
# ============================================================================

# STEP 1: TRAIN LORA

# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 1/6: Training LoRA from your photos"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Upload photos and get URLs (you'll need to host them)

echo "⚠️  Photos need to be publicly accessible URLs for LoRA training"

echo "Options:"
echo "  1. Upload to imgur.com and get direct links"

echo "  2. Use a file hosting service"

echo "  3. Run local web server"

echo ""

read -p "Have you uploaded photos and have URLs? (y/n): " has_urls

if [[ $has_urls =~ ^[Yy]$ ]]; then

    echo "Enter photo URLs (one per line, Ctrl+D when done):"

    PHOTO_URLS=()
    while IFS= read -r url; do

        PHOTO_URLS+=("$url")

    done

    echo "Training LoRA with ${#PHOTO_URLS[@]} images..."

    cd "$REPLIGEN_DIR"

    ruby33 repligen.rb << EOF
lora ${PHOTO_URLS[@]}
quit

EOF

    echo "✓ LoRA training initiated (takes ~30 minutes)"

    echo "The trained LoRA URL will be saved"

else
    echo "⏩ Skipping LoRA training for now"

    echo "You can train later with:"

    echo "  cd ~/repligen && ruby33 repligen.rb"

    echo "  repligen> lora https://url1.jpg https://url2.jpg ..."

fi

# ============================================================================

# STEP 2: MASTERPIECE GENERATION

# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 2/6: Generate base images with random chains"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Enter prompt for generation: " PROMPT

read -p "How many variations? (1-10): " VARIATIONS

for i in $(seq 1 $VARIATIONS); do
    echo "Generating variation $i/$VARIATIONS..."

    cd "$REPLIGEN_DIR"
    ruby33 repligen.rb << EOF

masterpiece $PROMPT
quit

EOF

done

echo "✓ Generated $VARIATIONS base images"

# ============================================================================

# STEP 3: UPSCALE & REMOVE BACKGROUND
# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 3/6: Upscale and remove backgrounds"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find generated images

GENERATED=$(find "$REPLIGEN_DIR" -name "masterpiece_*.jpg" -o -name "masterpiece_*.png" 2>/dev/null)

if [ -z "$GENERATED" ]; then
    echo "⚠️  No generated images found, skipping upscale/rembg"

else
    echo "Processing generated images..."

    for img in $GENERATED; do

        filename=$(basename "$img")

        echo "  Processing: $filename"
        # Use repligen to upscale

        cd "$REPLIGEN_DIR"

        ruby33 repligen.rb << EOF
chain 5 upscale and remove background for: $filename

quit

EOF

    done

    echo "✓ Upscale & background removal complete"

fi

# ============================================================================
# STEP 4: ANIMATE

# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 4/6: Animate images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find processed images

PROCESSED=$(find "$REPLIGEN_DIR" -name "*_upscale_*.jpg" -o -name "*_rembg_*.png" 2>/dev/null)

if [ -z "$PROCESSED" ]; then
    echo "⚠️  No processed images found, using originals"

    PROCESSED=$GENERATED
fi

for img in $PROCESSED; do

    echo "  Animating: $(basename $img)"

    cd "$REPLIGEN_DIR"
    ruby33 repligen.rb << EOF

chain 8 animate with camera motion and effects: $(basename $img)
quit

EOF

done

echo "✓ Animation complete"

# ============================================================================

# STEP 5: EXTEND & ADD MUSIC
# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 5/6: Extend animations and add music"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find generated videos

VIDEOS=$(find "$REPLIGEN_DIR" -name "masterpiece_*.mp4" 2>/dev/null)

if [ -z "$VIDEOS" ]; then
    echo "⚠️  No videos found, skipping music addition"

else
    if [ -f "$MUSIC_FILE" ]; then

        echo "Adding music to videos..."

        for video in $VIDEOS; do

            output="${video%.mp4}_with_music.mp4"

            echo "  Adding music to: $(basename $video)"
            ffmpeg -i "$video" -i "$MUSIC_FILE" \

                -c:v copy -c:a aac -shortest \

                -y "$output" 2>/dev/null
            echo "  ✓ Saved: $(basename $output)"

        done

        echo "✓ Music added to all videos"
    else

        echo "⚠️  No music file found at $MUSIC_FILE"
        echo "Upload music with:"

        echo "  scp /path/to/music.mp3 dev@185.52.176.18:~/music.mp3"

    fi

fi

# ============================================================================

# STEP 6: CRAZY RANDOM CHAINS

# ============================================================================
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "STEP 6/6: Generate crazy random chain variations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "How many random chain variations? (1-5): " RANDOM_CHAINS

for i in $(seq 1 $RANDOM_CHAINS); do

    RANDOM_LENGTH=$((RANDOM % 15 + 10))  # 10-25 steps
    echo "Creating random chain #$i with $RANDOM_LENGTH steps..."
    cd "$REPLIGEN_DIR"

    ruby33 repligen.rb << EOF

chain $RANDOM_LENGTH experimental creative chaos: $PROMPT
quit

EOF

done

echo "✓ Random chains complete"

# ============================================================================

# FINAL SUMMARY
# ============================================================================
echo ""

echo "╔═══════════════════════════════════════════════════════════════╗"

echo "║                  WORKFLOW COMPLETE! 🎉                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

echo ""

# Move everything to output

echo "📁 Organizing output..."

mkdir -p "$OUTPUT_DIR"
find "$REPLIGEN_DIR" -name "masterpiece_*" -exec mv {} "$OUTPUT_DIR/" \; 2>/dev/null || true

FINAL_COUNT=$(ls -1 "$OUTPUT_DIR" 2>/dev/null | wc -l)

echo "✓ Generated $FINAL_COUNT final files in $OUTPUT_DIR"

echo ""
echo "📊 Summary:"

echo "  Photos processed: $PHOTO_COUNT"
echo "  Variations created: $VARIATIONS"

echo "  Random chains: $RANDOM_CHAINS"

echo "  Total outputs: $FINAL_COUNT"

echo ""

echo "📥 Download results:"

echo "  scp -r dev@185.52.176.18:~/output/* /local/path/"

echo ""

echo "🎬 Your masterpieces are ready!"

