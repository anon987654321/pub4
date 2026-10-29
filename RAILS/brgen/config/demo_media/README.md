# Demo media

**A city network should look lived in on its first night, so the Bergen seeds carry photographs
made for them, and the app keeps those photographs inside its own tree.** A seed run on the
production box finds its pictures on disk instead of asking the internet for them.

The catalogue is bergen.yml. It maps each seed key to a picture and holds sixty-nine rows.
Sixty-four of them name a file in the images folder beside it, and each of those is marked
graded, because the frame has already been through postpro once and a second pass would stack a
second grain field on the first. The other five are Wikimedia Commons photographs of Bergen with
their credits written beside them, and those five are fetched over the network when the seed
runs.

Shared::DemoMedia looks a key up here first. A key the catalogue does not hold falls back to a
picsum landscape when the seed asks for a remote image, and to no picture at all when the seed
asks for the catalogue alone, as the bulk seeds do. A row whose file is missing is skipped with
a warning rather than raised, since one failed seed blocks every deploy. Setting SKIP_DEMO_MEDIA
turns attachment off, and the test environment never attaches. DEMO_MEDIA_CATALOG points the
lookup at a different catalogue, and DEMO_MEDIA_CITY at a different city's file.

The frames are prompts in STUDIO/replicate/lora/seed_media.yml, rendered on Replicate by
run_seed_media_replicate.rb in STUDIO/replicate/lora/_toolkit and filed here by
install_seed_media.rb. That script grades each frame at the preset its prompt names, never
overwrites a frame already filed, and caps the long edge at 1280 pixels. The four dating
portraits are general-model strangers, every one an adult, with no likeness of anyone real. The
prompt, model, seed, prediction and postpro preset of every render are recorded in
STUDIO/replicate/lora/seed_media_manifest.yml.

These graded copies are tracked in git, which is a deliberate exception to the rule against
committing generated assets. That rule keeps build output and renders out of history because
they can be made again from source. These cannot: a render costs money and never comes out the
same twice, and the deploy copies only tracked files to the box, where the seeds read them. So
the app keeps the small copy, and the full renders and their ungraded originals stay out of git
on the machine that made them.

Unprocessed sources receive one Postpro pass during the curated seed run. `preset: "random"`
chooses a valid preset deterministically from the seed key; repeating the seed does not change the
grade simply because the random number generator changed. A row marked `graded: true` is already
processed and must not receive a second pass.

For each new locally supplied image, record its source URL, source name, photographer,
photographer URL, license and/or required credit in the catalogue. Those details are copied to the
Active Storage blob metadata, and post cards/post pages can display a credit when one exists.
Do not bulk scrape Unsplash: its license excludes compiling its images to reproduce a similar or
competing service. Use the existing generated frames, the credited Wikimedia Commons sources, or
another source whose license permits the specific intended use.
