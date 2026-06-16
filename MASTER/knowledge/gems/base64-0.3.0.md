require "base64"

# Base64 utilities for UTF‑8 strings
#
# * `Base64.encode64` – adds a newline (`\n`) every 60 characters.
# * `Base64.strict_encode64` – produces a single‑line string, ideal for URLs or JSON.
# * `Base64.decode64` – decodes both strict and regular Base64 strings.

## Encode a UTF‑8 string
original = "Send reinforcements"

# Default encoding (includes a trailing newline)
encoded = Base64.encode64(original)
# => "U2VuZCByZWluZm9yY2VtZW50cw=\n"

# Strict encoding (no newline)
strict_encoded = Base64.strict_encode64(original)
# => "U2VuZCByZWluZm9yY2VtZW50cw="

## Decode back to UTF‑8
decoded = Base64.decode64(encoded)
# => "Send reinforcements"

# Decoding works with the strict variant as well
decoded_strict = Base64.decode64(strict_encoded)
# => "Send reinforcements"

## When to use which method
#
# * **Data transmission** – `strict_encode64` avoids unexpected line breaks.
# * **Human‑readable logs** – `encode64` splits long strings for readability.
# * **API payloads** – prefer the strict version to keep JSON compact.