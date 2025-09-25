# ---- Config ----
RID        ?= linux-x64
TFM        ?= net8.0
CONF       ?= Release
ROOT       := $(shell pwd)

MOD_PROJ   ?= src/WPStallman.GUI.Modern/WPStallman.GUI.csproj
LEG_PROJ   ?= src/WPStallman.GUI.Legacy/WPStallman.GUI.csproj

MOD_PUB    := $(ROOT)/src/WPStallman.GUI.Modern/bin/$(CONF)/$(TFM)/$(RID)/publish
LEG_PUB    := $(ROOT)/src/WPStallman.GUI.Legacy/bin/$(CONF)/$(TFM)/$(RID)/publish

DIST_DIR   := $(ROOT)/artifacts/dist
MOD_LABEL  ?= 2.39
LEG_LABEL  ?= 2.35

# ---- Targets ----
.PHONY: all modern legacy stage stage-only clean distclean

all: modern legacy stage

modern:
	@bash build/package/publish_modern_docker.sh

legacy:
	@bash build/package/publish_legacy_docker.sh

stage: stage-only

stage-only:
	@bash build/package/stage_variants.sh \
		"$(LEG_PUB)" "$(MOD_PUB)" \
		"$(DIST_DIR)" "$(LEG_LABEL)" "$(MOD_LABEL)" "$(RID)"

clean:
	@rm -rf $(MOD_PUB) $(LEG_PUB)

distclean:
	@rm -rf artifacts/dist
