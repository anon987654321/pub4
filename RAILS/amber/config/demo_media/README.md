# Demo media

**The demo wardrobe shows real garments beside the drawn ones, so a visitor sees
both the shape a piece takes on the figure and the cloth it is made of.** Every
photograph here is one garment or one outfit laid flat on a single backdrop, so
the clothes are the only thing that changes from frame to frame.

The catalogue in default.yml maps each seed key to a file in the images folder
beside it, and the seeder attaches the photograph second, after the drawn
cut-out, because the dressing room lays its zones over the first photo and the
cut-out is drawn for that. A row whose file is missing is skipped with a warning
rather than raised, since one failed seed blocks every deploy.

The frames are prompts in MASTER/tools/lora/seed_media.yml, rendered on Replicate and
graded by postpro before they arrive here, and each one's prompt, model, seed
and preset is recorded in MASTER/tools/lora/seed_media_manifest.yml. No person appears
in any of them.

These graded copies are tracked in git, which is a deliberate exception to the
rule against committing generated assets. That rule keeps build output and
renders out of history because they can be made again from source. These
cannot: a render costs money and never comes out the same twice, and the
deploy copies only tracked files to the box, where the seeds read them. So the
app keeps a small copy, 1280 pixels on the long edge, and the full renders stay
out of git on the machine that made them.
