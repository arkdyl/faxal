# title: Standard library
# These modules are written in Faxal itself and built into the faxal program
import "std/collections" as col
import "std/text"
import "std/iter" as it

let queue = col.Queue()
queue.push("first").push("second").push("third")
print(queue.pop(), queue)

let tags = col.set_of(["red", "green", "red", "blue"])
print(tags, tags.len())

print(text.title("a tiny language"), "|", text.pad_left(42, 6, "."), "|", text.commas(1234567))
print(it.group_by(["apple", "fig", "plum", "kiwi"], len))
