(* demo.sml -- parse a Petstore-lite OpenAPI 3.0 spec from YAML, inspect the
   typed model, then serialize it to JSON and confirm a round-trip. Also parse
   the equivalent JSON and confirm both encodings agree. Deterministic:
   identical output on every run / both compilers. *)

structure O = OpenApi

val yamlSpec =
  "openapi: '3.0.0'\n\
  \info:\n\
  \  title: Petstore\n\
  \  version: '1.0.0'\n\
  \paths:\n\
  \  /pets:\n\
  \    get:\n\
  \      operationId: listPets\n\
  \      responses:\n\
  \        '200':\n\
  \          description: A list of pets\n\
  \          content:\n\
  \            application/json:\n\
  \              schema:\n\
  \                type: array\n\
  \                items:\n\
  \                  $ref: '#/components/schemas/Pet'\n\
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
  \          type: string\n"

val spec = O.parseYaml yamlSpec

val () = print ("openapi: " ^ #openapi spec ^ "\n")
val () = print ("title:   " ^ #title (#info spec) ^ " v" ^ #version (#info spec) ^ "\n")

val () = print "paths:\n"
val () =
  List.app
    (fn (p, item) =>
        let
          fun m name NONE = ()
            | m name (SOME (op_ : O.operation)) =
                print ("  " ^ name ^ " " ^ p ^ "  -> "
                       ^ (case #operationId op_ of SOME i => i | NONE => "(anon)") ^ "\n")
        in
          m "GET " (#get item); m "POST" (#post item);
          m "PUT " (#put item); m "DEL " (#delete item)
        end)
    (#paths spec)

val () =
  case #components spec of
      SOME c =>
        print ("schemas: "
               ^ String.concatWith ", " (List.map #1 (#schemas c)) ^ "\n")
    | NONE => ()

val () = print "\nSerialized back to JSON:\n"
val () = print (O.toJson spec ^ "\n")

val reparsed = O.parseJson (O.toJson spec)
val () = print ("\nJSON round-trip equal: " ^ Bool.toString (O.equal (spec, reparsed)) ^ "\n")
