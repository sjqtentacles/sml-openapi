(* Tests for sml-openapi: a Petstore-lite OpenAPI 3.0 spec given in BOTH JSON
   and the equivalent YAML, asserting they parse to the same typed model, that
   the model fields are as expected, and that JSON/YAML serialization round-
   trips back to a structurally equal model. *)

structure Tests =
struct
  open Harness
  structure O = OpenApi

  (* ---- the JSON form ---- *)
  val jsonSpec =
    "{\n\
    \  \"openapi\": \"3.0.0\",\n\
    \  \"info\": {\n\
    \    \"title\": \"Petstore\",\n\
    \    \"version\": \"1.0.0\",\n\
    \    \"description\": \"A sample API\"\n\
    \  },\n\
    \  \"servers\": [ { \"url\": \"https://api.example.com/v1\" } ],\n\
    \  \"paths\": {\n\
    \    \"/pets\": {\n\
    \      \"get\": {\n\
    \        \"operationId\": \"listPets\",\n\
    \        \"summary\": \"List all pets\",\n\
    \        \"responses\": {\n\
    \          \"200\": {\n\
    \            \"description\": \"A list of pets\",\n\
    \            \"content\": {\n\
    \              \"application/json\": {\n\
    \                \"schema\": { \"type\": \"array\",\n\
    \                             \"items\": { \"$ref\": \"#/components/schemas/Pet\" } }\n\
    \              }\n\
    \            }\n\
    \          }\n\
    \        }\n\
    \      },\n\
    \      \"post\": {\n\
    \        \"operationId\": \"createPet\",\n\
    \        \"requestBody\": {\n\
    \          \"required\": true,\n\
    \          \"content\": {\n\
    \            \"application/json\": {\n\
    \              \"schema\": { \"$ref\": \"#/components/schemas/Pet\" }\n\
    \            }\n\
    \          }\n\
    \        },\n\
    \        \"responses\": { \"201\": { \"description\": \"Created\" } }\n\
    \      }\n\
    \    }\n\
    \  },\n\
    \  \"components\": {\n\
    \    \"schemas\": {\n\
    \      \"Pet\": {\n\
    \        \"type\": \"object\",\n\
    \        \"required\": [ \"id\", \"name\" ],\n\
    \        \"properties\": {\n\
    \          \"id\":   { \"type\": \"integer\", \"format\": \"int64\" },\n\
    \          \"name\": { \"type\": \"string\" },\n\
    \          \"tag\":  { \"type\": \"string\" }\n\
    \        }\n\
    \      }\n\
    \    }\n\
    \  }\n\
    \}"

  (* ---- the equivalent YAML form ---- *)
  val yamlSpec =
    "openapi: '3.0.0'\n\
    \info:\n\
    \  title: Petstore\n\
    \  version: '1.0.0'\n\
    \  description: A sample API\n\
    \servers:\n\
    \  - url: 'https://api.example.com/v1'\n\
    \paths:\n\
    \  /pets:\n\
    \    get:\n\
    \      operationId: listPets\n\
    \      summary: List all pets\n\
    \      responses:\n\
    \        '200':\n\
    \          description: A list of pets\n\
    \          content:\n\
    \            application/json:\n\
    \              schema:\n\
    \                type: array\n\
    \                items:\n\
    \                  $ref: '#/components/schemas/Pet'\n\
    \    post:\n\
    \      operationId: createPet\n\
    \      requestBody:\n\
    \        required: true\n\
    \        content:\n\
    \          application/json:\n\
    \            schema:\n\
    \              $ref: '#/components/schemas/Pet'\n\
    \      responses:\n\
    \        '201':\n\
    \          description: Created\n\
    \components:\n\
    \  schemas:\n\
    \    Pet:\n\
    \      type: object\n\
    \      required:\n\
    \        - id\n\
    \        - name\n\
    \      properties:\n\
    \        id:\n\
    \          type: integer\n\
    \          format: int64\n\
    \        name:\n\
    \          type: string\n\
    \        tag:\n\
    \          type: string\n"

  fun runAll () =
    let
      val mj = O.parseJson jsonSpec
      val my = O.parseYaml yamlSpec

      (* ---------- top-level fields ---------- *)
      val () = section "top-level document"
      val () = checkString "openapi version" ("3.0.0", #openapi mj)
      val () = checkString "info.title" ("Petstore", #title (#info mj))
      val () = checkString "info.version" ("1.0.0", #version (#info mj))
      val () = checkBool "info.description present"
                 (true, #description (#info mj) = SOME "A sample API")
      val () = checkInt "one server" (1, List.length (#servers mj))
      val () = checkString "server url"
                 ("https://api.example.com/v1", #url (hd (#servers mj)))
      val () = checkInt "one path" (1, List.length (#paths mj))

      (* ---------- the /pets path ---------- *)
      val () = section "/pets path item"
      val (ppath, pitem) = hd (#paths mj)
      val () = checkString "path key" ("/pets", ppath)
      val () = checkBool "has get" (true, isSome (#get pitem))
      val () = checkBool "has post" (true, isSome (#post pitem))
      val () = checkBool "no delete" (false, isSome (#delete pitem))

      val getOp = valOf (#get pitem)
      val () = checkBool "get.operationId" (true, #operationId getOp = SOME "listPets")
      val () = checkBool "get.summary" (true, #summary getOp = SOME "List all pets")
      val () = checkInt "get has one response" (1, List.length (#responses getOp))
      val (code, resp) = hd (#responses getOp)
      val () = checkString "response code" ("200", code)
      val () = checkString "response description" ("A list of pets", #description resp)

      (* array schema with $ref items *)
      val (mt, arrSchema) = hd (#content resp)
      val () = checkString "media type" ("application/json", mt)
      val () =
        check "200 schema is an array of $ref Pet"
          (case arrSchema of
               O.Schema { stype = SOME "array",
                          items = SOME (O.Schema { sref = SOME r, ... }), ... } =>
                 r = "#/components/schemas/Pet"
             | _ => false)

      val postOp = valOf (#post pitem)
      val () = checkBool "post.operationId" (true, #operationId postOp = SOME "createPet")
      val rb = valOf (#requestBody postOp)
      val () = checkBool "requestBody required" (true, #required rb)
      val () =
        check "requestBody schema is $ref Pet"
          (case #content rb of
               [ (_, O.Schema { sref = SOME r, ... }) ] => r = "#/components/schemas/Pet"
             | _ => false)

      (* ---------- components.schemas.Pet ---------- *)
      val () = section "components.schemas.Pet"
      val comps = valOf (#components mj)
      val (pname, petSchema) = hd (#schemas comps)
      val () = checkString "schema name" ("Pet", pname)
      val () =
        check "Pet object with required + ordered properties"
          (case petSchema of
               O.Schema { stype = SOME "object", required = ["id", "name"],
                          properties = [ ("id", O.Schema { stype = SOME "integer",
                                                           sformat = SOME "int64", ... }),
                                         ("name", O.Schema { stype = SOME "string", ... }),
                                         ("tag", O.Schema { stype = SOME "string", ... }) ],
                          ... } => true
             | _ => false)

      (* ---------- JSON form == YAML form ---------- *)
      val () = section "JSON and YAML parse to the same model"
      val () = checkBool "models structurally equal" (true, O.equal (mj, my))

      (* ---------- round-trips ---------- *)
      val () = section "round-trips"
      val () = checkBool "parseJson (toJson m) = m" (true, O.equal (O.parseJson (O.toJson mj), mj))
      val () = checkBool "parseYaml (toYaml m) = m" (true, O.equal (O.parseYaml (O.toYaml mj), mj))
      val () = checkBool "toJson then re-parse equals YAML model"
                 (true, O.equal (O.parseJson (O.toJson my), mj))
      val () = checkBool "auto-detect parse JSON" (true, O.equal (O.parse jsonSpec, mj))
      val () = checkBool "auto-detect parse YAML" (true, O.equal (O.parse yamlSpec, mj))

      (* ---------- errors ---------- *)
      val () = section "errors"
      val () = checkRaises "parseJson raises on garbage" (fn () => O.parseJson "{ not valid")
      val () = checkBool "parseOpt NONE on garbage" (true, not (isSome (O.parseOpt "{ : : :")))
      val () = checkBool "parseOpt SOME on valid" (true, isSome (O.parseOpt jsonSpec))
    in
      Harness.run ()
    end

  val run = runAll
end
