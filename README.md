# sml-openapi

[![CI](https://github.com/sjqtentacles/sml-openapi/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-openapi/actions/workflows/ci.yml)

A typed model of **OpenAPI 3.0** documents with parsers and serializers for
both the **YAML** and **JSON** encodings, in pure Standard ML. JSON input is
parsed by the vendored [sml-json](https://github.com/sjqtentacles/sml-json);
YAML input by the vendored [sml-yaml](https://github.com/sjqtentacles/sml-yaml).
Both forms build the *same* `openapi` model, so a spec written in YAML and the
equivalent JSON parse equal.

No FFI, threads, clock or randomness: the same input always builds the same
model and serializes to the same bytes under **MLton** and **Poly/ML**. Paths,
properties, responses and parameters keep document order, and the model holds
no `real` values, so it admits ordinary structural equality and round-trips:
`parse` ∘ `toJson` ∘ `parse` (and the YAML pair) yield an equal model.

- Typed model: `openapi` / `info` / `server` / `pathItem` (operations keyed by
  method) / `operation` / `parameter` / `requestBody` / `response` / `schema`
  (`type` / `format` / `properties` / `items` / `required` / `$ref` / `enum`)
  / `components`.
- `parse` auto-detects the syntax (first non-space byte `{`/`[` ⇒ JSON, else
  YAML); `parseJson` / `parseYaml` force one. `toJson` / `toYaml` serialize.

## API

```sml
structure OpenApi : sig
  datatype schema = Schema of
    { sref : string option, stype : string option, sformat : string option
    , properties : (string * schema) list, items : schema option
    , required : string list, enum : string list }
  type info       = { title : string, version : string, description : string option }
  type server     = { url : string, description : string option }
  type parameter  = { name : string, location : string, required : bool
                    , description : string option, schema : schema option }
  type mediaType  = string * schema
  type response   = { description : string, content : mediaType list }
  type requestBody = { description : string option, required : bool, content : mediaType list }
  type operation  = { operationId : string option, summary : string option
                    , description : string option, parameters : parameter list
                    , requestBody : requestBody option, responses : (string * response) list }
  type pathItem   = { get : operation option, put : operation option, post : operation option
                    , delete : operation option, patch : operation option }
  type components = { schemas : (string * schema) list }
  type openapi    = { openapi : string, info : info, servers : server list
                    , paths : (string * pathItem) list, components : components option }

  exception OpenApiError of string
  val parse     : string -> openapi      (* auto-detect YAML/JSON; raises *)
  val parseJson : string -> openapi
  val parseYaml : string -> openapi
  val parseOpt  : string -> openapi option
  val toJson    : openapi -> string      (* 2-space indented JSON *)
  val toYaml    : openapi -> string      (* block-style YAML *)
  val equal     : openapi * openapi -> bool
end
```

## Example

```sml
val spec = OpenApi.parseYaml
  "openapi: '3.0.0'\n\
  \info: { title: Petstore, version: '1.0.0' }\n\
  \paths:\n\
  \  /pets:\n\
  \    get: { operationId: listPets, responses: { '200': { description: ok } } }"

val "Petstore" = #title (#info spec)
val SOME op_   = #get (#2 (hd (#paths spec)))
val SOME "listPets" = #operationId op_
val true = OpenApi.equal (spec, OpenApi.parseJson (OpenApi.toJson spec))
```

Running [`examples/demo.sml`](examples/demo.sml) with `make example` prints:

```
openapi: 3.0.0
title:   Petstore v1.0.0
paths:
  GET  /pets  -> listPets
schemas: Pet

Serialized back to JSON:
{
  "openapi": "3.0.0",
  "info": {
    "title": "Petstore",
    "version": "1.0.0"
  },
  "paths": {
    "/pets": {
      "get": {
        "operationId": "listPets",
        "responses": {
          "200": {
            "description": "A list of pets",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "$ref": "#/components/schemas/Pet"
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Pet": {
        "type": "object",
        "required": [
          "id",
          "name"
        ],
        "properties": {
          "id": {
            "type": "integer",
            "format": "int64"
          },
          "name": {
            "type": "string"
          }
        }
      }
    }
  }
}

JSON round-trip equal: true
```

## Build & test

Requires [MLton](http://mlton.org/) and/or [Poly/ML](https://polyml.org/).

```sh
make test        # build + run the suite under MLton
make test-poly   # run the suite under Poly/ML
make all-tests   # both
make example     # build + run the demo
make clean
```

## Why both sml-yaml and sml-json are vendored

sml-yaml supports JSON-style *flow* syntax, but it cannot parse a real,
multi-line JSON OpenAPI document (it stops at the leading `{` with
`expected 'key: value' but got: {`). So JSON input is handled by sml-json
(which parses multi-line JSON reliably) and YAML input by sml-yaml; both adapt
to the shared `Json.json` AST that the model is built from. Each vendored
dependency bundles its own `sml-parsec`; the two copies are byte-identical, and
only sml-json's is linked (sml-yaml keeps its copy `local` and does not use it).

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-openapi
smlpkg sync
```

Reference `src/openapi.mlb` from your own `.mlb` (MLton / MLKit); it pulls in
the vendored `sml-json` and `sml-yaml` cores. For Poly/ML, load the sources in
the order used by the `test-poly` target in the [`Makefile`](Makefile).

## Layout

```
sml.pkg                                       smlpkg manifest (requires sml-json, sml-yaml)
Makefile                                      MLton + Poly/ML targets
.github/workflows/ci.yml                      CI: MLton + Poly/ML
src/
  openapi.sig    OPENAPI signature (typed model + API)
  openapi.sml    model, YAML/JSON parsers and serializers
  openapi.mlb    public basis (brings in vendored sml-json + sml-yaml)
lib/github.com/sjqtentacles/sml-json/         VENDORED sml-json  (+ its sml-parsec)
lib/github.com/sjqtentacles/sml-yaml/         VENDORED sml-yaml  (+ its sml-parsec)
examples/
  demo.sml       parse YAML / inspect / serialize JSON / round-trip
test/
  harness.sml    shared assertion harness
  test.sml       Petstore-lite in JSON and YAML; equality + round-trips (39 checks)
  entry.sml / main.sml
tools/polybuild  Poly/ML build wrapper
```

## Tests

39 deterministic checks against a Petstore-lite OpenAPI 3.0 spec supplied in
**both** JSON and the equivalent YAML: top-level fields, servers, the `/pets`
path with `get` (operationId `listPets`, a `200` response whose schema is an
array of `$ref` `#/components/schemas/Pet`) and `post` (a required
`requestBody` referencing `Pet`), and `components.schemas.Pet` (an object with
`required` `[id, name]` and ordered, typed/formatted properties). The two
encodings are asserted to parse to the same model, and both JSON and YAML
serialization are re-parsed to confirm structural round-trips. Run
`make all-tests` to verify identical output under both compilers.

Integers are handled losslessly. `sml-json`'s `JInt` and `sml-yaml`'s `Int`
both carry an arbitrary-precision `IntInf.int`, so the YAML↔JSON bridge is the
identity — a value larger than a machine `int` (e.g. a millisecond epoch such
as `1700000000000`, past 2^31) parses, converts and re-serializes without loss
or overflow. This holds identically under MLton (whose default `int` is a
fixed-width 32-bit type) and Poly/ML (a fixed-width 63-bit `int`); on both,
`IntInf` is arbitrary precision. A dedicated boundary test exercises this path
end to end (it previously crashed, because the bridge narrowed via
`IntInf.toInt` and the parser used fixed-width `Int.fromString`/`Int.toString`).

## License

MIT. See [LICENSE](LICENSE).
