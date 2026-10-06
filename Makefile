# Run from gamified_bubbles_analysis/.

PYTHON ?= .venv/bin/python
ifeq ($(wildcard $(PYTHON)),)
  PYTHON := python3
endif

export PYTHONPATH := src/build

.PHONY: help analyze figures-slides panels session payments robustness clean-interim

help:
	@echo "Reproduce the paper tables and figures:"
	@echo "  make analyze             -> output/tables/*.tex and output/figures/*"
	@echo ""
	@echo "Optional:"
	@echo "  make figures-slides      16:9 copies for the Beamer deck"
	@echo "  make panels              Rebuild processed panels from raw oTree exports"
	@echo "  make session ID=20260512 Process one session into data/interim/"
	@echo "  make payments ID=20260512 Write data/payments/payments_{id}.xlsx"
	@echo "  make robustness ID=20261006"
	@echo "                           Main sample + an include:false session ->"
	@echo "                           data/processed/with_{id}/ and output/with_{id}/"
	@echo "  make clean-interim       Delete rebuildable data/interim/ panels"

analyze:
	Rscript src/analyze/descriptive_statistics.R
	Rscript src/analyze/regressions.R
	$(PYTHON) src/analyze/figures.py

figures-slides:
	$(PYTHON) src/analyze/figures.py --slides

panels:
	$(PYTHON) src/build/build_panels.py

session:
	@test -n "$(ID)" || (echo "Usage: make session ID=20260512"; exit 1)
	$(PYTHON) src/build/process_session.py --session $(ID)

payments:
	@test -n "$(ID)" || (echo "Usage: make payments ID=20260512"; exit 1)
	$(PYTHON) src/build/process_payments.py --session $(ID)

# Robustness: rebuild panels with an excluded session force-included and run
# the full analysis into a side folder. data/processed/ and output/ untouched.
robustness:
	@test -n "$(ID)" || (echo "Usage: make robustness ID=20261006"; exit 1)
	$(PYTHON) src/build/build_panels.py --force-include $(ID) --out-dir data/processed/with_$(ID)
	GB_PROCESSED_DIR=$(CURDIR)/data/processed/with_$(ID) GB_OUTPUT_DIR=$(CURDIR)/output/with_$(ID) \
		Rscript src/analyze/descriptive_statistics.R
	GB_PROCESSED_DIR=$(CURDIR)/data/processed/with_$(ID) GB_OUTPUT_DIR=$(CURDIR)/output/with_$(ID) \
		Rscript src/analyze/regressions.R
	GB_PROCESSED_DIR=$(CURDIR)/data/processed/with_$(ID) GB_OUTPUT_DIR=$(CURDIR)/output/with_$(ID) \
		$(PYTHON) src/analyze/figures.py
	@echo "Robustness outputs in output/with_$(ID)/ (compare with output/)"

clean-interim:
	rm -rf data/interim/*
	@echo "Removed data/interim/* (raw and processed untouched)"
