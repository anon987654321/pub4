# Merethe identity LoRA

This subject follows the path already used by \`Studio::Visual::IdeaPicture\`:
\`STUDIO/replicate/lora/<subject>/\`. Do not create a second \`STUDIO/lora/\`
implementation; \`IdeaPicture::SUBJECTS\` already points here.

## Privacy

The 15 source photographs are recovered into the local \`sources/\` directory.
That directory, \`dataset/\`, \`.cache/\`, \`weights/\`, outputs and training artefacts
are ignored by Git. Do not use \`git add -f\` for the photos, derived crops,
dataset ZIP, captions attached to private photos, or trained weights. A subject's
agreement to training is not a blanket decision to publish her photographs or
weights.

This package does not upload images, create a Replicate training, or generate
images. Those are separate operator actions. Keep the destination model private
unless the subject separately agrees to publication and distribution.

## Recover and prepare

From the repository root:

\`\`\`sh
ruby STUDIO/replicate/lora/merethe/prepare.rb --recover
\`\`\`

This downloads the 15 historical originals from commit
\`8e1955ae130592ab7c20ee266c024f061431c67e\` into the ignored local \`sources/\`
folder and verifies every file against its original Git blob SHA-1. Originals
are not modified.

The first face-led curation contains only \`10.jpg\` through \`13.jpg\`. The other
archived frames remain available in \`sources/\` but are not placed in the general
identity dataset by default: some are low-resolution, overlaid with text or
stickers, lack a visible face, or use intimate/cropped framing. In particular,
this avoids teaching a general-purpose identity model from intimate images.

Four clean portraits are not enough for a reliable first training. Add at least
six more suitable photos (eight to fourteen is better) to the local, ignored
folder \`STUDIO/replicate/lora/merethe/sources/additional/\`. Prefer ordinary,
non-intimate photos with her face clearly visible, varied expressions, angles,
clothing and everyday settings. Avoid filters, stickers, text overlays, heavy
retouching and repeated near-duplicates. Each image needs a same-basename \`.txt\`
caption in that folder, and the caption must include the trigger word \`MERETHE\`.

Example pair:

\`\`\`text
sources/additional/photo-01.jpg
sources/additional/photo-01.txt
\`\`\`

After adding and reviewing the images, run:

\`\`\`sh
ruby STUDIO/replicate/lora/merethe/prepare.rb
\`\`\`

The preflight refuses fewer than 10 or more than 18 images, missing captions,
invalid caption triggers and missing/corrupt archived sources. It builds a
private ZIP only after these checks pass. The report is written to the ignored
\`.cache/prepare_report.json\`. The target is 12–18 images, in line with the
trainer's dataset guidance.

## Training plan — not executed

- Trainer: \`ostris/flux-dev-lora-trainer\`
- Pinned trainer version: \`26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2\`
- Trigger: \`MERETHE\`
- Initial steps: \`1000\`
- LoRA rank: \`16\`
- Destination: a private Replicate model selected by the operator; do not guess
  the account name.

The version pin matches \`STUDIO/replicate/client.rb\`. The current trainer README
recommends 12–18 varied subject images, and its training form documents caption
sidecars, 1,000–3,000 typical steps and rank 16–32. The initial 1,000 / rank 16
plan is deliberately conservative. Reassess captions and sample outputs before
any second run.

A separate explicit approval is required before uploading the ZIP or starting
paid training. No provider call is made by \`prepare.rb\`.

## Subject environment

Copy \`subject.env.example\` to the ignored local \`subject.env\` if you want
\`STUDIO/photograph.rb --subject merethe\` to resolve the subject descriptor after
a private training manifest exists under \`weights/merethe/replicate_training.json\`.
Do not put API tokens in this file.
