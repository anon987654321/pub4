# `postpro.rb`

**Where Code Meets Celluloid Soul.** `postpro.rb` is more than a tool—it's a translator for the forgotten language of light, chemistry, and mechanics. It captures the **visceral, human feel** of analog capture and applies it to digital pixels with scientific precision.

<img width="896" height="512" alt="1" src="https://gist.github.com/user-attachments/assets/2b9aba19-b90e-4fe8-902a-1f193e617407" />

---

**The Cinematic Emotion Engine.** Apply physically accurate analog film emulation—grain, halation, weave—through scientific models in Ruby. Not a filter; a translator for celluloid soul.

[![Ruby](https://img.shields.io/badge/Ruby-3.0+-cc342d?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![libvips](https://img.shields.io/badge/libvips-8.10+-5a6bab)](https://libvips.github.io/libvips/)

---

## Install

```zsh
# Install the engine
gem install ruby-vips

# Transform an image (creates 'your_photo_blockbuster.jpg')
ruby postpro.rb your_photo.jpg --preset blockbuster

# Or, run interactively
ruby postpro.rb
```

---

## Presets

*   **`portrait`**: Warm, intimate. Kodak Portra skin tones.
*   **`blockbuster`**: Epic, theatrical. Halation, teal/orange contrast.
*   **`street`**: Gritty, urgent. High-contrast Tri-X grain.
*   **`dream`**: Subjective, soft. Leica glow, color bleed.

Presets are defined in [`postpro.rb`](./postpro.rb) and configured via [`master.yml`](./master.yml).

---

## How It Works

A physically-based pipeline:
1.  Converts image to linear light.
2.  Applies film stock color and H&D characteristic curves.
3.  Adds optical effects (halation, bloom).
4.  Encodes for display and overlays texture (AR grain, gate weave).

This order ensures effects feel authentic, not applied.

---

### A Final Note on the Craft

This tool is built on a simple, radical idea: that the **"feel"** of analog media is not a mystery, but a set of measurable, physical phenomena. By understanding the *why*—why halation feels romantic, why grain feels tactile, why a lifted black feels nostalgic—you gain not just a set of filters, but a **director's control over time, texture, and emotion.**

**Postpro.rb** is your lens into that control. Now go make something that feels.
