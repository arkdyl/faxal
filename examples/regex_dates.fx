# title: Regex and dates
import "std/regex" as re
import "std/datetime" as dt

let log = "2026-10-03 error disk full | 2026-10-04 warn slow | 2026-10-05 error timeout"
for m in re.find_all("(?<day>\\d{4}-\\d\\d-\\d\\d) error (?<what>[a-z ]+?)(?: \\||$)", log) {
  let day = dt.parse(m.named.day)
  print(day.format("%a %d %b"), "->", m.named.what)
}
print(re.replace("(\\w+)@(\\w+)\\.com", "write to ada@home.com", "$1 at $2"))
print(re.split("\\s*[,;]\\s*", "one , two;three"))

let launch = dt.make(2026, 12, 25)
print("days left:", dt.make(2026, 10, 3).days_until(launch))
print(launch.format("%A"), launch.add_months(2).format("%B %Y"))
