# sml-openapi build
#
#   make            build the test binary with MLton (default)
#   make test       build + run tests under MLton
#   make test-poly  run tests under Poly/ML (use-and-run; no link step)
#   make all-tests  run the suite under both compilers
#   make example    build + run examples/demo.sml
#   make clean      remove build artifacts
#
# Layout B (dependent): own sources live in src/. Two parsers are vendored:
# sml-json (JSON, bundles sml-parsec) and sml-yaml (YAML). sml-yaml keeps its
# own sml-parsec copy local; it is byte-identical to sml-json's, so a single
# consistent parsec is what actually links.

MLTON      ?= mlton
POLY       ?= poly
BIN        := bin
JSONDIR    := lib/github.com/sjqtentacles/sml-json
YAMLDIR    := lib/github.com/sjqtentacles/sml-yaml/lib/github.com/sjqtentacles/sml-yaml
PARSEC     := $(JSONDIR)/lib/github.com/sjqtentacles/sml-parsec
TEST_MLB   := test/sources.mlb
SRCS       := $(wildcard $(PARSEC)/*.sml $(PARSEC)/*.sig $(PARSEC)/*.mlb) \
              $(wildcard $(JSONDIR)/src/*.sml $(JSONDIR)/src/*.sig $(JSONDIR)/src/*.mlb) \
              $(wildcard $(YAMLDIR)/*.sml $(YAMLDIR)/*.sig $(YAMLDIR)/*.mlb) \
              $(wildcard src/*.sml src/*.sig src/*.mlb) \
              $(wildcard test/*.sml) $(TEST_MLB)

.PHONY: all test poly test-poly all-tests example clean

all: $(BIN)/test-mlton

example: $(BIN)/demo
	./$(BIN)/demo

$(BIN)/demo: $(SRCS) examples/demo.sml examples/sources.mlb | $(BIN)
	$(MLTON) -output $@ examples/sources.mlb

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

# Poly/ML has no native .mlb support; the suite runs at top level and exits on
# its own. Load the vendored sml-parsec first (canonical parsec.mlb order), then
# sml-json, then sml-yaml (which does not itself use parsec), then the OpenAPI
# model, then the test driver.
poly test-poly:
	printf 'use "$(PARSEC)/stream.sig";\nuse "$(PARSEC)/parsec.sig";\nuse "$(PARSEC)/parsecfn.sml";\nuse "$(PARSEC)/charstream.sml";\nuse "$(PARSEC)/charparseccore.sml";\nuse "$(PARSEC)/charparsec.sig";\nuse "$(PARSEC)/charparsec.sml";\nuse "$(PARSEC)/expr.sig";\nuse "$(PARSEC)/exprfn.sml";\nuse "$(PARSEC)/charexpr.sml";\nuse "$(PARSEC)/tokenstream.sml";\nuse "$(JSONDIR)/src/json.sig";\nuse "$(JSONDIR)/src/json.sml";\nuse "$(JSONDIR)/src/jsonPretty.sml";\nuse "$(YAMLDIR)/yaml.sig";\nuse "$(YAMLDIR)/yaml.sml";\nuse "src/openapi.sig";\nuse "src/openapi.sml";\nuse "test/harness.sml";\nuse "test/test.sml";\nuse "test/entry.sml";\nuse "test/main.sml";\n' | $(POLY) -q --error-exit

all-tests: test test-poly

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -f $(BIN)/test-mlton $(BIN)/demo
