# std/datetime: dates and times (UTC), written in Faxal.
#
#   import "std/datetime" as dt
#   let d = dt.make(2026, 10, 3, 14, 30)
#   print(d)                                   # 2026-10-03 14:30:00
#   print(d.format("%A, %d %B %Y"))            # Saturday, 03 October 2026
#   print(d.add_days(30).format("%Y-%m-%d")) # 2026-11-02
#   print(dt.parse("2026-12-25").days_until(d))
#   print(dt.now().year)
#
# A DateTime counts seconds since 1970-01-01 00:00:00 UTC. Fields: year, month, day, hour, minute, second, ts.

let MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
let DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
let _CUMULATIVE = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

fn is_leap(year) { return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) }

fn days_in_month(year, month) {
  if month == 2 { return is_leap(year) and 29 or 28 }
  if month == 4 or month == 6 or month == 9 or month == 11 { return 30 }
  return 31
}

# Days since 1970-01-01 for a calendar date (proleptic Gregorian).
fn _days_from_civil(y, m, d) {
  if m <= 2 { y -= 1 }
  let era = math.floor(y / 400)
  let yoe = y - era * 400
  let mp = (m + 9) % 12
  let doy = math.floor((153 * mp + 2) / 5) + d - 1
  let doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

fn _civil_from_days(z) {
  z += 719468
  let era = math.floor(z / 146097)
  let doe = z - era * 146097
  let yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  let mp = math.floor((5 * doy + 2) / 153)
  let d = doy - math.floor((153 * mp + 2) / 5) + 1
  let m = mp < 10 and mp + 3 or mp - 9
  return [m <= 2 and y + 1 or y, m, d]
}

fn _two(n) { return str(n).pad_left(2, "0") }

class DateTime {
  fn init(ts) {
    self.ts = math.floor(ts)
    let days = math.floor(self.ts / 86400)
    let rest = self.ts - days * 86400
    let civil = _civil_from_days(days)
    self.year = civil[0]
    self.month = civil[1]
    self.day = civil[2]
    self.hour = math.floor(rest / 3600)
    self.minute = math.floor(rest % 3600 / 60)
    self.second = rest % 60
    self.days = days
  }

  # 0 = Monday ... 6 = Sunday
  fn weekday() { return (self.days + 3) % 7 }
  fn day_of_year() { return _CUMULATIVE[self.month - 1] + self.day + (self.month > 2 and is_leap(self.year) and 1 or 0) }

  fn add_seconds(n) { return DateTime(self.ts + n) }
  fn add_minutes(n) { return DateTime(self.ts + n * 60) }
  fn add_hours(n) { return DateTime(self.ts + n * 3600) }
  fn add_days(n) { return DateTime(self.ts + n * 86400) }

  # Moves by whole months, keeping the day when it exists (Jan 31 + 1 month = Feb 28 or 29).
  fn add_months(n) {
    let total = self.year * 12 + (self.month - 1) + n
    let y = math.floor(total / 12)
    let m = total % 12 + 1
    let limit = days_in_month(y, m)
    let d = self.day > limit and limit or self.day
    return DateTime(_days_from_civil(y, m, d) * 86400 + self.hour * 3600 + self.minute * 60 + self.second)
  }
  fn add_years(n) { return self.add_months(n * 12) }

  fn diff(other) { return self.ts - other.ts }
  fn days_until(other) { return math.floor((other.ts - self.ts) / 86400) }
  fn is_before(other) { return self.ts < other.ts }
  fn is_after(other) { return self.ts > other.ts }
  fn start_of_day() { return DateTime(self.days * 86400) }

  fn format(pattern = "%Y-%m-%d %H:%M:%S") {
    let out = ""
    let chars = pattern.chars()
    let i = 0
    while i < len(chars) {
      let c = chars[i]
      if c != "%" or i + 1 >= len(chars) { out += c; i += 1; continue }
      let f = chars[i + 1]
      i += 2
      if f == "Y" { out += str(self.year) }
      else if f == "y" { out += _two(self.year % 100) }
      else if f == "m" { out += _two(self.month) }
      else if f == "d" { out += _two(self.day) }
      else if f == "e" { out += str(self.day) }
      else if f == "H" { out += _two(self.hour) }
      else if f == "I" { out += _two((self.hour + 11) % 12 + 1) }
      else if f == "M" { out += _two(self.minute) }
      else if f == "S" { out += _two(self.second) }
      else if f == "p" { out += self.hour < 12 and "AM" or "PM" }
      else if f == "B" { out += MONTHS[self.month - 1] }
      else if f == "b" { out += MONTHS[self.month - 1][0:3] }
      else if f == "A" { out += DAYS[self.weekday()] }
      else if f == "a" { out += DAYS[self.weekday()][0:3] }
      else if f == "j" { out += str(self.day_of_year()).pad_left(3, "0") }
      else if f == "u" { out += str(self.weekday() + 1) }
      else if f == "s" { out += str(self.ts) }
      else if f == "%" { out += "%" }
      else { out += "%" + f }
    }
    return out
  }

  fn to_str() { return self.format() }
}

fn make(year, month = 1, day = 1, hour = 0, minute = 0, second = 0) {
  if month < 1 or month > 12 { throw "month must be 1 to 12, got " + str(month) }
  if day < 1 or day > days_in_month(year, month) { throw "day out of range for " + str(year) + "-" + str(month) + ": " + str(day) }
  if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59 { throw "time out of range" }
  return DateTime(_days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second)
}

fn from_timestamp(ts) { return DateTime(ts) }
fn now() { return DateTime(time.now()) }
fn today() { return now().start_of_day() }

# Reads "2026-10-03", "2026-10-03 14:30" or "2026-10-03T14:30:05" (a trailing Z is ignored).
fn parse(text) {
  let s = text.trim().replace("T", " ")
  if s.ends_with("Z") { s = s[0:len(s) - 1] }
  let halves = s.split(" ")
  let date = halves[0].split("-")
  if len(halves) > 2 or len(date) != 3 { throw "can't read a date from " + repr(text) + " (use YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)" }
  let clock = len(halves) == 2 and halves[1].split(":") or ["0", "0", "0"]
  if len(clock) < 2 or len(clock) > 3 { throw "can't read a time from " + repr(text) }
  for part in date + clock {
    if not part.is_digit() { throw "can't read a date from " + repr(text) }
  }
  let sec = len(clock) == 3 and int(clock[2]) or 0
  return make(int(date[0]), int(date[1]), int(date[2]), int(clock[0]), int(clock[1]), sec)
}
