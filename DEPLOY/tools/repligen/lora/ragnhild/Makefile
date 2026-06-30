ROOT := /Users/mac/Documents/GitHub/pub4
MASTER := $(ROOT)/MASTER
LORA_ROOT := $(ROOT)/DEPLOY/tools/repligen/lora/ragnhild
SOURCES := $(LORA_ROOT)/sources/selfie.jpg $(LORA_ROOT)/sources/grok-video-65b87ee9-af88-40ae-92f7-6f6c5a713f34.mp4 $(LORA_ROOT)/sources/grok-video-fcc56478-53fb-467a-8c39-4fed2ca57ae4.mp4
DESTINATION ?= basicfeatures/ragnhild
TRIGGER ?= ragnhild
VERSION ?= v2
V2_VERSION ?=

.PHONY: v2-prepare v2-local v2-replicate v2-video

v2-prepare:
	cd $(MASTER) && bundle exec ruby bin/video lora-train \
		--name $(TRIGGER) \
		--trigger $(TRIGGER) \
		--destination $(DESTINATION) \
		--version $(VERSION) \
		--prepare-only \
		--curation ranked \
		--max-images 60 \
		--max-per-source 35 \
		--min-frame-gap 8 \
		--rank 32 \
		--steps 2000 \
		$(SOURCES)

v2-local:
	cd $(MASTER) && bundle exec ruby bin/video lora-train \
		--name $(TRIGGER) \
		--trigger $(TRIGGER) \
		--local \
		--version $(VERSION) \
		--curation ranked \
		--max-images 60 \
		--max-per-source 35 \
		--min-frame-gap 8 \
		--rank 32 \
		--steps 2000 \
		--lr 1e-4 \
		--caption-dropout 0.05 \
		$(SOURCES)

v2-replicate:
	cd $(MASTER) && bundle exec ruby bin/video lora-train \
		--name $(TRIGGER) \
		--trigger $(TRIGGER) \
		--destination $(DESTINATION) \
		--version $(VERSION) \
		--curation ranked \
		--max-images 60 \
		--max-per-source 35 \
		--min-frame-gap 8 \
		--rank 32 \
		--steps 2000 \
		$(SOURCES)

v2-video:
	test -n "$(V2_VERSION)"
	cd $(MASTER) && bundle exec ruby bin/video \
		--backend kling \
		--minutes 0.1 \
		--lora $(DESTINATION):$(V2_VERSION) \
		"$(TRIGGER), woman, intimate analog portrait, daylight through a window, soft natural smile, realistic skin texture, Kodak Portra 400, gentle handheld micro push-in, shallow depth of field"
