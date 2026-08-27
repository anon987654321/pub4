#!/usr/bin/env ruby
# frozen_string_literal: true

# Turn shoots.yml into prompts, for whichever subject is being rendered.
#
# The fifty sittings are subject-agnostic: a north window is a north window
# whoever stands in it. What changes per subject is the trigger token the LoRA
# was trained on and the descriptor that anchors age and appearance, and both of
# those live in that subject's subject.env. So the same fifty render for anyone.
#
# Read by render_config.rb when LORA_PROMPT_SET=shoots, and usable on its own:
#
#   ruby _toolkit/shoots.rb ragnhild            # every prompt, numbered
#   ruby _toolkit/shoots.rb ragnhild --side=Weather
#   ruby _toolkit/shoots.rb ragnhild --only=3,7,12

require "yaml"
require "pathname"

LORA_ROOT = Pathname.new(__dir__).join("..").expand_path
SHOOTS_FILE = LORA_ROOT.join("shoots.yml")

# CLIP's text encoder takes 77 tokens and discards the rest without saying so, so
# a prompt that runs long loses its tail — which is where the film stock and the
# focal length are. Counted here rather than hoped about.
#
# This is an approximation of BPE, not BPE: roughly one token per word plus one
# per punctuation mark, which runs slightly high on ordinary English. Erring high
# is the right direction for a ceiling. The 12 training prompts measured 39-48
# under it and none were truncated.
TOKEN_LIMIT = 77

def approximate_tokens(prompt)
  prompt.scan(/[\w'-]+|[[:punct:]]/).length + 2 # +2 for CLIP's start and end markers
end

def subject_env(subject)
  path = LORA_ROOT.join(subject, "subject.env")
  raise "no subject.env at #{path}" unless path.file?

  Hash[path.read.lines.filter_map do |line|
    key, value = line.strip.split("=", 2)
    [key, value] if value && !key.start_with?("#")
  end]
end

# The order is deliberate: who, then what they look like, then where they are,
# then how it is lit, then how it was shot. CLIP weights earlier tokens more
# heavily, so identity comes before scenery and scenery before equipment.
def prompt_for(shoot, trigger:, descriptor:)
  [trigger,
   descriptor,
   shoot.fetch("scene"),
   "key light #{shoot.fetch('key')}",
   "#{shoot.fetch('distance')} from camera",
   shoot.fetch("lens"),
   shoot.fetch("stock")].join(", ")
end

def shoots(side: nil, only: nil)
  all = YAML.load_file(SHOOTS_FILE).fetch("shoots")
  all = all.select { |s| s["side"].casecmp?(side) } if side
  all = all.select { |s| only.include?(s["n"]) } if only
  all
end

def prompts_for(subject, side: nil, only: nil)
  env = subject_env(subject)
  trigger = env.fetch("TRIGGER")
  descriptor = env.fetch("DESCRIPTOR") do
    raise "#{subject}/subject.env has no DESCRIPTOR — shoots.yml needs one to anchor age and appearance"
  end
  shoots(side: side, only: only).map { |s| [s, prompt_for(s, trigger: trigger, descriptor: descriptor)] }
end

if $PROGRAM_NAME == __FILE__
  subject = ARGV.shift or abort "warn: usage: shoots.rb <subject> [--side=NAME] [--only=1,2,3]"
  side = ARGV.grep(/\A--side=/).first&.split("=", 2)&.last
  only = ARGV.grep(/\A--only=/).first&.split("=", 2)&.last&.split(",")&.map(&:to_i)

  over = []
  prompts_for(subject, side: side, only: only).each do |shoot, prompt|
    tokens = approximate_tokens(prompt)
    over << shoot["title"] if tokens > TOKEN_LIMIT
    puts format("%02d  %-22s %3d tok  %s", shoot["n"], shoot["title"], tokens, prompt)
  end

  unless over.empty?
    warn ""
    warn "warn: #{over.length} prompt(s) exceed CLIP's #{TOKEN_LIMIT} tokens and will be"
    warn "warn: truncated silently, losing the stock and focal length at the tail:"
    over.each { |title| warn "warn:   #{title}" }
    exit 1
  end
end
