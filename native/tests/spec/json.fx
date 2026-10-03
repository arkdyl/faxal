print(json.encode([1, "two", true, nil, {k: 1.5}]))        # expect: [1,"two",true,null,{"k":1.5}]
print(json.encode({a: {b: [1, 2]}}, 2))                    # expect: {
                                                           # expect:   "a": {
                                                           # expect:     "b": [
                                                           # expect:       1,
                                                           # expect:       2
                                                           # expect:     ]
                                                           # expect:   }
                                                           # expect: }
print(json.encode("quote\" back\\ nl\n tab\t"))             # expect: "quote\" back\\ nl\n tab\t"
let d = json.decode("{\"name\": \"Ada\", \"langs\": [\"a\", \"b\"], \"n\": -1.5e2, \"ok\": true, \"none\": null, \"u\": \"\\u00e9\\n\"}")
print(d.name, d.langs, d.n, d.ok, d.none == nil, d.u == "é\n")   # expect: Ada ["a", "b"] -150 true true true
print(json.decode("[]"), json.decode("{}"), json.decode(" 42 "), json.decode("\"s\""))   # expect: [] {} 42 s
let round = json.decode(json.encode({list: [1, 2, {x: "y"}], s: "é"}))
print(round)                                               # expect: {list: [1, 2, {x: "y"}], s: "é"}
try { json.decode("[1, 2") } catch e { print(e) }          # expect: Invalid JSON: Expected ',' or ']' at position 5
try { json.encode(print) } catch e { print(e) }            # expect: json.encode: can't encode a function
