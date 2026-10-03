# cli-only
let data = {name: "Faxal", version: 1, tags: ["small", "fast"], nested: {ok: true}}
let text = json.encode(data, 2)
print(text)
let back = json.decode(text)
print(back.tags[1], back.nested.ok)
