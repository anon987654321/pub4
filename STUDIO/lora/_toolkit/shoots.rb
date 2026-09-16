#!/usr/bin/env ruby
# frozen_string_literal: true

# Turn ideas.yml into prompts, for whichever subject is being rendered.
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
#   ruby _toolkit/shoots.rb ragnhild --set=scenarios

require "yaml"
require "pathname"
# preprompt composes the prompt and counts its tokens; this file chooses the
# sittings and the subject.
require_relative "../../preprompt/lib/craft"

LORA_ROOT = Pathname.new(__dir__).join("..").expand_path

# Every written sitting lives in ideas.yml, tagged with the brief it belongs to.
#
# shoots is a record of light and it flatters; warp is the press shoot and it is
# not trying to. Mixing them produces an average of the two, which is the one
# thing neither brief wants, so a set is a filter on that file rather than a
# blend of it. best is the short list, and it names sittings in the other two
# rather than copying their prose.
#
# The drawn sets have no entries there at all: preprompt draws their sittings by
# number, and each is capped only when nothing narrows it. scenarios are
# portraits in drawn situations, selfies keep a selfie's framing and gaze from
# two or three metres, and distance is one sitting at six stated camera
# distances.
IDEAS = LORA_ROOT.join("ideas.yml")
BEST = "best"
DRAWN_SETS = {
  "scenarios" => [:scenario_sitting, 24],
  "selfies" => [:selfie_sitting, 48],
  "distance" => [:distance_sitting, DISTANCE_LADDER.length],
}.freeze

def ideas_document
  @ideas_document ||= YAML.safe_load_file(IDEAS)
end

def written_sets
  ideas_document.fetch("sets").keys + [BEST]
end

def available_sets
  (written_sets + DRAWN_SETS.keys).sort
end

def subject_env(subject)
  path = LORA_ROOT.join(subject, "subject.env")
  raise "no subject.env at #{path}" unless path.file?

  Hash[path.read.lines.filter_map do |line|
    key, value = line.strip.split("=", 2)
    [key, unquote(value)] if value && !key.start_with?("#")
  end]
end

# subject.env is shell, and toolkit.sh sources it. So a value containing spaces has
# to be quoted, and a Ruby reader that splits on "=" and stops has to take the
# quotes back off or they reach the prompt as characters.
#
# Both halves were wrong at once: DESCRIPTOR was written unquoted, so `. subject.env`
# under `set -eu` parsed `DESCRIPTOR=47` and then tried to run `year`, exiting 127
# before the renderer started. Quoting fixed the shell and broke Ruby, which then
# put literal quotation marks in front of Ragnhild's description. Two parsers for
# one file, and it has to satisfy both.
def unquote(value)
  text = value.to_s.strip
  return text[1..-2].to_s if text.length >= 2 && (text.start_with?('"') && text.end_with?('"') ||
                                                  text.start_with?("'") && text.end_with?("'"))

  text
end

# Drawn sets are numbered from one, so --only=30 is scenario 30 even though the
# unfiltered set stops at its cap. The distance ladder has six rungs and no
# more, so a number past it draws nothing.
def drawn_sittings(set, side: nil, only: nil)
  composer, count = DRAWN_SETS.fetch(set)
  all = (only || (1..count)).filter_map { |number| send(composer, number) }
  side ? all.select { |s| s["side"].casecmp?(side) } : all
end

def shoots(side: nil, only: nil, set: nil)
  return drawn_sittings(set, side: side, only: only) if DRAWN_SETS.key?(set)

  set ||= "shoots"
  abort "warn: no set #{set.inspect} — have: #{available_sets.join(', ')}" unless written_sets.include?(set)

  all = if set == BEST
          resolve_selection(ideas_document.fetch(BEST))
        else
          ideas_document.fetch("ideas").select { |sitting| sitting["set"] == set }
        end
  all = all.select { |s| s["side"].casecmp?(side) } if side
  all = all.select { |s| only.include?(s["n"]) } if only
  all
end

# A curated set names sittings in other sets rather than copying them.
#
# A copy drifts. The first time a scene is reworded in the shoots set the duplicate
# in the short list still says the old thing, two files describe the same sitting
# differently, and nothing indicates which one rendered. So the short list is
# { from:, n: } and the prose has exactly one home.
#
# Renumbered so a short list reads 1..24 rather than carrying the numbers it was
# drawn from, and the source is kept on each so a frame can be traced back.
def resolve_selection(entries)
  entries.each_with_index.map do |entry, index|
    source = entry.fetch("from")
    number = entry.fetch("n")
    found = shoots(set: source).find { |sitting| sitting["n"] == number }
    abort "warn: best names #{source} ##{number}, which does not exist" unless found

    found.merge("n" => index + 1, "source" => "#{source}##{number}", "why" => entry["why"])
  end
end

def prompts_for(subject, side: nil, only: nil, set: nil)
  env = subject_env(subject)
  trigger = env.fetch("TRIGGER")
  descriptor = env.fetch("DESCRIPTOR") do
    raise "#{subject}/subject.env has no DESCRIPTOR — a set needs one to anchor age and appearance"
  end
  shoots(side: side, only: only, set: set).map { |s| [s, sitting_prompt(s, trigger: trigger, descriptor: descriptor)] }
end

if $PROGRAM_NAME == __FILE__
  subject = ARGV.shift or
    abort "warn: usage: shoots.rb <subject> [--set=NAME] [--side=NAME] [--only=1,2,3]\n" \
          "warn: sets: #{available_sets.join(', ')}"
  set = ARGV.grep(/\A--set=/).first&.split("=", 2)&.last
  side = ARGV.grep(/\A--side=/).first&.split("=", 2)&.last
  only = ARGV.grep(/\A--only=/).first&.split("=", 2)&.last&.split(",")&.map(&:to_i)

  over = []
  prompts_for(subject, side: side, only: only, set: set).each do |shoot, prompt|
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
