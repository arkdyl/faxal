# std/path: file path helpers, written in Faxal. Paths use "/" (Windows accepts it too).
#
#   import "std/path" as path
#   path.join("a", "b", "c.txt")     # "a/b/c.txt"  (or path.join(["a", "b", "c.txt"]))
#   path.basename("/x/y/z.tar.gz")   # "z.tar.gz"
#   path.dirname("/x/y/z.tar.gz")    # "/x/y"
#   path.ext("z.tar.gz")             # ".gz"
#   path.stem("z.tar.gz")            # "z.tar"
#   path.normalize("a/./b/../c")     # "a/c"

fn _unix(p) { return p.replace("\\", "/") }

fn is_absolute(p) {
  p = _unix(p)
  return p.starts_with("/") or (len(p) >= 3 and p[1] == ":" and p[2] == "/")
}

# Joins up to six pieces, or pass one list of pieces. An absolute piece restarts the path.
fn join(a, b = nil, c = nil, d = nil, e = nil, f = nil) {
  let pieces = type(a) == "list" and a or [a, b, c, d, e, f]
  let out = ""
  for piece in pieces {
    if piece == nil or piece == "" { continue }
    piece = _unix(piece)
    if out == "" or piece.starts_with("/") { out = piece }
    else if out.ends_with("/") { out += piece }
    else { out += "/" + piece }
  }
  return out
}

fn basename(p) {
  p = _unix(p)
  while len(p) > 1 and p.ends_with("/") { p = p[0:len(p) - 1] }
  let cut = -1
  for k in 0..len(p) { if p[k] == "/" { cut = k } }
  return p[cut + 1:]
}

fn dirname(p) {
  p = _unix(p)
  while len(p) > 1 and p.ends_with("/") { p = p[0:len(p) - 1] }
  let cut = -1
  for k in 0..len(p) { if p[k] == "/" { cut = k } }
  if cut < 0 { return "." }
  if cut == 0 { return "/" }
  return p[0:cut]
}

fn ext(p) {
  let name = basename(p)
  let dot = -1
  for k in 0..len(name) { if name[k] == "." { dot = k } }
  if dot <= 0 { return "" }
  return name[dot:]
}

fn stem(p) {
  let name = basename(p)
  let e = ext(name)
  return name[0:len(name) - len(e)]
}

fn split(p) { return [dirname(p), basename(p)] }

fn normalize(p) {
  p = _unix(p)
  let absolute = p.starts_with("/")
  let parts = []
  for part in p.split("/") {
    if part == "" or part == "." { continue }
    if part == ".." {
      if len(parts) > 0 and parts[-1] != ".." { parts.pop() }
      else if not absolute { parts.push("..") }
    } else {
      parts.push(part)
    }
  }
  let out = parts.join("/")
  if absolute { return "/" + out }
  return out == "" and "." or out
}

fn with_ext(p, new_ext) {
  let e = ext(p)
  return p[0:len(p) - len(e)] + new_ext
}
