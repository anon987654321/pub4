# Demo media

**Every seeded post, profile, listing and dish in Bergen carries a photograph
made for it, and the app carries those photographs itself.** A seed run on the
production box needs no network to look finished, and a picture always shows
what its words describe.

The catalogue in bergen.yml maps each seed key to a file in the images folder
beside it. Shared::DemoMedia looks a key up here before it falls back to a
picsum landscape, and a row marked graded is attached as it is, because it has
already been through postpro once. A row whose file is missing is skipped with a
warning rather than raised, since one failed seed blocks every deploy.

The frames are prompts in MASTER/tools/lora/seed_media.yml, rendered on Replicate by
run_seed_media_replicate.rb in MASTER/tools/lora/_toolkit and filed here by
install_seed_media.rb, which grades nothing twice and never overwrites a frame
already filed. The people are general-model strangers, every one an adult, with
no likeness of anyone real. Each render's prompt, model, seed, prediction and
postpro preset is recorded in MASTER/tools/lora/seed_media_manifest.yml.

These graded copies are tracked in git, which is a deliberate exception to the
rule against committing generated assets. That rule keeps build output and
renders out of history because they can be made again from source. These
cannot: a render costs money and never comes out the same twice, and the
deploy copies only tracked files to the box, where the seeds read them. So the
app keeps a small copy, 1280 pixels on the long edge, and the full renders and
their ungraded originals stay out of git on the machine that made them.
