# store.fx: the notes, kept in memory and saved to a JSON file after every change.
#
#   import "store.fx" as store
#   let s = store.Store("notes.json")             # loads the file if it exists
#   let n = s.add("Buy milk", tags = ["home"])    # {id: 1, text: "Buy milk", tags: ["home"], created: "...", updated: "..."}
#   s.search(query = "milk")                      # notes whose text contains it (any case)

import "std/datetime" as dt

class Store {
  fn init(file: str or nil = nil) {
    self.file = file
    self.notes = []
    self.next_id = 1
    if file != nil and fs.exists(file) {
      let data = json.decode(fs.read(file))
      self.notes = data.notes
      self.next_id = data.next_id
    }
  }

  fn _save() {
    if self.file == nil { return }
    # write a temporary file and rename it over the real one is not possible yet, so write it in one go
    fs.write(self.file, json.encode({next_id: self.next_id, notes: self.notes}, 2))
  }

  fn _stamp() => dt.now().format("%Y-%m-%dT%H:%M:%SZ")

  fn add(text: str, tags: list = []) -> map {
    let clean = text.trim()
    if clean == "" { throw "a note needs some text" }
    if len(clean) > 10000 { throw "a note can have at most 10000 characters" }
    let note = {id: self.next_id, text: clean, tags: self._clean_tags(tags), created: self._stamp(), updated: self._stamp()}
    self.next_id += 1
    self.notes.push(note)
    self._save()
    return note
  }

  fn _clean_tags(tags: list) -> list {
    let out = []
    for t in tags {
      let tag = str(t).trim().lower()
      if tag != "" and not out.contains(tag) { out.push(tag) }
    }
    return out
  }

  fn get(id: num) -> map or nil {
    for n in self.notes { if n.id == id { return n } }
    return nil
  }

  # Changes the text and/or the tags of a note (leave one out to keep it). nil when there is no such note.
  fn update(id: num, text: str or nil = nil, tags: list or nil = nil) -> map or nil {
    let note = self.get(id)
    if note == nil { return nil }
    if text != nil {
      if text.trim() == "" { throw "a note needs some text" }
      note.text = text.trim()
    }
    if tags != nil { note.tags = self._clean_tags(tags) }
    note.updated = self._stamp()
    self._save()
    return note
  }

  fn remove(id: num) -> bool {
    for i in 0..len(self.notes) {
      if self.notes[i].id == id {
        self.notes.remove(i)
        self._save()
        return true
      }
    }
    return false
  }

  # newest first; query matches the text, tag matches one tag exactly
  fn search(query: str or nil = nil, tag: str or nil = nil) -> list {
    let q = query == nil and "" or query.lower()
    let found = self.notes.filter(fn(n) => n.text.lower().contains(q) and (tag == nil or n.tags.contains(tag.lower())))
    return found.reversed()
  }

  # how many notes each tag has
  fn tag_counts() -> map {
    let counts = {}
    for n in self.notes { for t in n.tags { counts[t] = counts.get(t, 0) + 1 } }
    return counts
  }
}
