(* openapi.sml -- a typed OpenAPI 3.0 model with YAML + JSON parsers and
   serializers. Both syntaxes are funnelled through the vendored sml-json
   `Json.json` AST: JSON input is parsed directly by sml-json, YAML input is
   parsed by sml-yaml and adapted to `Json.json`. Serialization goes the other
   way (model -> Json.json -> JSON text, or -> Yaml.t -> YAML text). *)

structure OpenApi :> OPENAPI =
struct
  (* ===================== model ===================== *)
  datatype schema = Schema of
    { sref       : string option
    , stype      : string option
    , sformat    : string option
    , properties : (string * schema) list
    , items      : schema option
    , required   : string list
    , enum       : string list }

  type info =
    { title : string, version : string, description : string option }
  type server = { url : string, description : string option }
  type parameter =
    { name : string, location : string, required : bool
    , description : string option, schema : schema option }
  type mediaType = string * schema
  type response = { description : string, content : mediaType list }
  type requestBody =
    { description : string option, required : bool, content : mediaType list }
  type operation =
    { operationId : string option, summary : string option
    , description : string option, parameters : parameter list
    , requestBody : requestBody option, responses : (string * response) list }
  type pathItem =
    { get : operation option, put : operation option, post : operation option
    , delete : operation option, patch : operation option }
  type components = { schemas : (string * schema) list }
  type openapi =
    { openapi : string, info : info, servers : server list
    , paths : (string * pathItem) list, components : components option }

  exception OpenApiError of string
  fun oerr m = raise OpenApiError m

  val emptySchema =
      Schema { sref = NONE, stype = NONE, sformat = NONE, properties = [],
               items = NONE, required = [], enum = [] }

  (* ===================== Json.json helpers ===================== *)
  fun asObj (Json.JObj kvs) = kvs
    | asObj _ = oerr "expected a JSON/YAML object"
  fun asArr (Json.JArr xs) = xs
    | asArr _ = oerr "expected a JSON/YAML array"
  fun find kvs k = Option.map #2 (List.find (fn (k2, _) => k2 = k) kvs)

  (* Render any scalar to a string (used for `required` / `enum` members). *)
  fun scalarStr (Json.JStr s)  = s
    | scalarStr (Json.JInt n)  = Int.toString n
    | scalarStr (Json.JBool b) = Bool.toString b
    | scalarStr Json.JNull     = "null"
    | scalarStr (Json.JReal _) = oerr "unexpected real scalar"
    | scalarStr _              = oerr "expected a scalar"

  fun strField kvs k =
      case find kvs k of
          SOME (Json.JStr s) => s
        | SOME _ => oerr ("field '" ^ k ^ "' must be a string")
        | NONE => oerr ("missing required field '" ^ k ^ "'")
  fun optStr kvs k =
      case find kvs k of
          SOME (Json.JStr s) => SOME s
        | SOME Json.JNull => NONE
        | SOME _ => oerr ("field '" ^ k ^ "' must be a string")
        | NONE => NONE
  fun boolField kvs k =
      case find kvs k of SOME (Json.JBool b) => b | _ => false

  (* ===================== model <- Json.json ===================== *)
  fun schemaOf j =
      let
        val kvs = asObj j
        val properties =
            case find kvs "properties" of
                SOME p => List.map (fn (k, v) => (k, schemaOf v)) (asObj p)
              | NONE => []
        val items =
            case find kvs "items" of SOME it => SOME (schemaOf it) | NONE => NONE
        val required =
            case find kvs "required" of
                SOME r => List.map scalarStr (asArr r) | NONE => []
        val enum =
            case find kvs "enum" of
                SOME e => List.map scalarStr (asArr e) | NONE => []
      in
        Schema { sref = optStr kvs "$ref", stype = optStr kvs "type",
                 sformat = optStr kvs "format", properties = properties,
                 items = items, required = required, enum = enum }
      end

  fun contentOf j =
      List.map
        (fn (mt, mtobj) =>
            let val mkvs = asObj mtobj
            in (mt, case find mkvs "schema" of
                        SOME s => schemaOf s | NONE => emptySchema)
            end)
        (asObj j)

  fun responseOf j =
      let val kvs = asObj j
      in { description = (case find kvs "description" of
                              SOME (Json.JStr s) => s | _ => ""),
           content = (case find kvs "content" of
                          SOME c => contentOf c | NONE => []) }
      end

  fun parameterOf j =
      let val kvs = asObj j
      in { name = strField kvs "name", location = strField kvs "in",
           required = boolField kvs "required",
           description = optStr kvs "description",
           schema = (case find kvs "schema" of
                         SOME s => SOME (schemaOf s) | NONE => NONE) }
      end

  fun requestBodyOf j =
      let val kvs = asObj j
      in { description = optStr kvs "description",
           required = boolField kvs "required",
           content = (case find kvs "content" of
                          SOME c => contentOf c | NONE => []) }
      end

  fun operationOf j =
      let val kvs = asObj j
      in { operationId = optStr kvs "operationId",
           summary = optStr kvs "summary",
           description = optStr kvs "description",
           parameters = (case find kvs "parameters" of
                             SOME ps => List.map parameterOf (asArr ps) | NONE => []),
           requestBody = (case find kvs "requestBody" of
                              SOME rb => SOME (requestBodyOf rb) | NONE => NONE),
           responses = (case find kvs "responses" of
                            SOME r => List.map (fn (c, ro) => (c, responseOf ro)) (asObj r)
                          | NONE => []) }
      end

  fun pathItemOf j =
      let
        val kvs = asObj j
        fun m name = case find kvs name of SOME ob => SOME (operationOf ob) | NONE => NONE
      in
        { get = m "get", put = m "put", post = m "post",
          delete = m "delete", patch = m "patch" }
      end

  fun componentsOf j =
      let val kvs = asObj j
      in { schemas = (case find kvs "schemas" of
                          SOME s => List.map (fn (k, v) => (k, schemaOf v)) (asObj s)
                        | NONE => []) }
      end

  fun serverOf j =
      let val kvs = asObj j
      in { url = strField kvs "url", description = optStr kvs "description" } end

  fun infoOf j =
      let val kvs = asObj j
      in { title = strField kvs "title", version = strField kvs "version",
           description = optStr kvs "description" }
      end

  fun modelFromJson j =
      let val kvs = asObj j
      in { openapi = strField kvs "openapi",
           info = (case find kvs "info" of
                       SOME i => infoOf i | NONE => oerr "missing 'info'"),
           servers = (case find kvs "servers" of
                          SOME ss => List.map serverOf (asArr ss) | NONE => []),
           paths = (case find kvs "paths" of
                        SOME p => List.map (fn (k, v) => (k, pathItemOf v)) (asObj p)
                      | NONE => []),
           components = (case find kvs "components" of
                             SOME c => SOME (componentsOf c) | NONE => NONE) }
      end

  (* ===================== Yaml.t <-> Json.json ===================== *)
  fun yamlToJson y =
      case y of
          Yaml.Null    => Json.JNull
        | Yaml.Bool b  => Json.JBool b
        | Yaml.Int i   => Json.JInt (IntInf.toInt i)
        | Yaml.Float r => Json.JReal r
        | Yaml.Str s   => Json.JStr s
        | Yaml.Seq xs  => Json.JArr (List.map yamlToJson xs)
        | Yaml.Map kvs => Json.JObj (List.map (fn (k, v) => (k, yamlToJson v)) kvs)

  fun jsonToYaml j =
      case j of
          Json.JNull   => Yaml.Null
        | Json.JBool b => Yaml.Bool b
        | Json.JInt n  => Yaml.Int (IntInf.fromInt n)
        | Json.JReal r => Yaml.Float r
        | Json.JStr s  => Yaml.Str s
        | Json.JArr xs => Yaml.Seq (List.map jsonToYaml xs)
        | Json.JObj kvs => Yaml.Map (List.map (fn (k, v) => (k, jsonToYaml v)) kvs)

  (* ===================== parsing ===================== *)
  fun parseJson s =
      case Json.parseJson s of
          CharParsec.Ok j => modelFromJson j
        | CharParsec.Err e => raise OpenApiError (CharParsec.errorToString e)

  fun parseYaml s =
      modelFromJson (yamlToJson (Yaml.parse s))
      handle Fail m => raise OpenApiError m

  fun looksLikeJson s =
      let
        fun skip i =
            if i >= String.size s then NONE
            else let val c = String.sub (s, i)
                 in if c = #" " orelse c = #"\t" orelse c = #"\n" orelse c = #"\r"
                    then skip (i + 1) else SOME c
                 end
      in
        case skip 0 of SOME #"{" => true | SOME #"[" => true | _ => false
      end

  fun parse s = if looksLikeJson s then parseJson s else parseYaml s
  fun parseOpt s = SOME (parse s) handle OpenApiError _ => NONE

  (* ===================== model -> Json.json ===================== *)
  fun optField k NONE = []
    | optField k (SOME s) = [(k, Json.JStr s)]

  fun schemaToJson (Schema s) =
      Json.JObj (
        optField "$ref" (#sref s)
        @ optField "type" (#stype s)
        @ optField "format" (#sformat s)
        @ (case #required s of [] => []
             | r => [("required", Json.JArr (List.map Json.JStr r))])
        @ (case #enum s of [] => []
             | e => [("enum", Json.JArr (List.map Json.JStr e))])
        @ (case #items s of NONE => []
             | SOME it => [("items", schemaToJson it)])
        @ (case #properties s of [] => []
             | ps => [("properties",
                       Json.JObj (List.map (fn (k, v) => (k, schemaToJson v)) ps))]))

  fun contentToJson content =
      Json.JObj (List.map (fn (mt, sch) =>
                    (mt, Json.JObj [("schema", schemaToJson sch)])) content)

  fun responseToJson ({ description, content } : response) =
      Json.JObj ([("description", Json.JStr description)]
                 @ (case content of [] => [] | c => [("content", contentToJson c)]))

  fun parameterToJson ({ name, location, required, description, schema } : parameter) =
      Json.JObj ([("name", Json.JStr name), ("in", Json.JStr location)]
                 @ (if required then [("required", Json.JBool true)] else [])
                 @ optField "description" description
                 @ (case schema of NONE => [] | SOME sc => [("schema", schemaToJson sc)]))

  fun requestBodyToJson ({ description, required, content } : requestBody) =
      Json.JObj (optField "description" description
                 @ (if required then [("required", Json.JBool true)] else [])
                 @ (case content of [] => [] | c => [("content", contentToJson c)]))

  fun operationToJson ({ operationId, summary, description, parameters,
                         requestBody, responses } : operation) =
      Json.JObj (
        optField "operationId" operationId
        @ optField "summary" summary
        @ optField "description" description
        @ (case parameters of [] => []
             | ps => [("parameters", Json.JArr (List.map parameterToJson ps))])
        @ (case requestBody of NONE => []
             | SOME rb => [("requestBody", requestBodyToJson rb)])
        @ (case responses of [] => []
             | rs => [("responses",
                       Json.JObj (List.map (fn (c, r) => (c, responseToJson r)) rs))]))

  fun pathItemToJson ({ get, put, post, delete, patch } : pathItem) =
      let fun op1 name NONE = []
            | op1 name (SOME ob) = [(name, operationToJson ob)]
      in
        Json.JObj (op1 "get" get @ op1 "post" post @ op1 "put" put
                   @ op1 "delete" delete @ op1 "patch" patch)
      end

  fun componentsToJson ({ schemas } : components) =
      Json.JObj (case schemas of [] => []
                   | s => [("schemas",
                            Json.JObj (List.map (fn (k, v) => (k, schemaToJson v)) s))])

  fun serverToJson ({ url, description } : server) =
      Json.JObj ([("url", Json.JStr url)] @ optField "description" description)

  fun infoToJson ({ title, version, description } : info) =
      Json.JObj ([("title", Json.JStr title), ("version", Json.JStr version)]
                 @ optField "description" description)

  fun modelToJson ({ openapi, info, servers, paths, components } : openapi) =
      Json.JObj (
        [("openapi", Json.JStr openapi), ("info", infoToJson info)]
        @ (case servers of [] => []
             | ss => [("servers", Json.JArr (List.map serverToJson ss))])
        @ [("paths", Json.JObj (List.map (fn (k, v) => (k, pathItemToJson v)) paths))]
        @ (case components of NONE => []
             | SOME c => [("components", componentsToJson c)]))

  (* ===================== serialization ===================== *)
  fun toJson m = JsonPretty.toStringIndent 2 (modelToJson m)
  fun toYaml m = Yaml.toString (jsonToYaml (modelToJson m))

  fun equal (a : openapi, b : openapi) = a = b
end
