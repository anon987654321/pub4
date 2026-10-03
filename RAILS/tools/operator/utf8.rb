# frozen_string_literal: true

# OPERATOR command-line tools inspect UTF-8 source and configuration regardless
# of the operator's locale. Minimal OpenBSD and CI environments may otherwise
# default Ruby file reads to US-ASCII.
Encoding.default_external = Encoding::UTF_8

