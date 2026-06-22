(* openapi.sig

   A typed model of OpenAPI 3.0 documents with parsers and serializers for both
   the YAML and JSON encodings, in pure Standard ML.

   Input handling is split across two vendored parsers: JSON documents go
   through sml-json (which reliably parses multi-line JSON), and YAML documents
   go through sml-yaml. Both forms build the *same* `openapi` model, so a spec
   written in YAML and the equivalent JSON parse equal. `parse` auto-detects the
   syntax (a document whose first non-space byte is `{` or `[` is treated as
   JSON, otherwise YAML).

   The model preserves *source/document order* for paths, properties, responses
   and parameters, so the model is deterministic and round-trips: re-serializing
   and re-parsing yields a structurally equal model. The model contains no
   `real` values, so it admits ordinary structural equality (`=`); `equal` is
   exposed for convenience.

   No FFI, threads, clock or randomness: same input, same model and same bytes
   under MLton and Poly/ML. *)

signature OPENAPI =
sig
  (* A JSON Schema object (the subset used by OpenAPI 3 component/inline
     schemas). All fields are optional/possibly-empty; `$ref` is carried in
     `sref` and, when present, the other fields are normally empty. *)
  datatype schema = Schema of
    { sref       : string option            (* "$ref": "#/components/..."   *)
    , stype      : string option            (* "type": object/string/...    *)
    , sformat    : string option            (* "format": int64/date-time/.. *)
    , properties : (string * schema) list   (* object properties, in order  *)
    , items      : schema option            (* array element schema         *)
    , required   : string list              (* required property names       *)
    , enum       : string list }            (* enum values (rendered scalars)*)

  type info =
    { title : string, version : string, description : string option }

  type server = { url : string, description : string option }

  type parameter =
    { name        : string
    , location    : string                  (* the OpenAPI "in" field        *)
    , required    : bool
    , description : string option
    , schema      : schema option }

  type mediaType = string * schema          (* media type -> schema          *)

  type response =
    { description : string
    , content     : mediaType list }        (* e.g. ("application/json", _)   *)

  type requestBody =
    { description : string option
    , required    : bool
    , content     : mediaType list }

  type operation =
    { operationId : string option
    , summary     : string option
    , description : string option
    , parameters  : parameter list
    , requestBody : requestBody option
    , responses   : (string * response) list }   (* status code -> response   *)

  type pathItem =
    { get    : operation option
    , put    : operation option
    , post   : operation option
    , delete : operation option
    , patch  : operation option }

  type components = { schemas : (string * schema) list }

  type openapi =
    { openapi    : string
    , info       : info
    , servers    : server list
    , paths      : (string * pathItem) list
    , components : components option }

  (* Raised on a parse error or a structurally invalid document. *)
  exception OpenApiError of string

  (* Parse YAML or JSON (auto-detected). Raises `OpenApiError`. *)
  val parse     : string -> openapi
  (* Force one syntax. *)
  val parseJson : string -> openapi
  val parseYaml : string -> openapi
  (* Non-raising auto-detecting variant. *)
  val parseOpt  : string -> openapi option

  (* Serialize. Output is deterministic and re-parses to an equal model. *)
  val toJson : openapi -> string             (* 2-space indented JSON         *)
  val toYaml : openapi -> string             (* block-style YAML              *)

  (* Structural equality (the model has no reals, so this is just `=`). *)
  val equal : openapi * openapi -> bool
end
