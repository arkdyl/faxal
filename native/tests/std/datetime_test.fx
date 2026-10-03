import "std/test" as t
import "std/datetime" as dt

t.test("make and format", fn() {
  let d = dt.make(2026, 10, 3, 14, 30)
  t.eq(str(d), "2026-10-03 14:30:00")
  t.eq(d.format("%A, %d %B %Y"), "Saturday, 03 October 2026")
  t.eq(d.format("%I:%M %p %a %b %j %e %y %%"), "02:30 PM Sat Oct 276 3 26 %")
  t.eq(d.weekday(), 5)
  t.eq(dt.make(2000, 2, 29).weekday(), 1)
})

t.test("timestamps round trip", fn() {
  t.eq(str(dt.from_timestamp(0)), "1970-01-01 00:00:00")
  t.eq(str(dt.from_timestamp(1700000000)), "2023-11-14 22:13:20")
  t.eq(str(dt.from_timestamp(-86400)), "1969-12-31 00:00:00")
  for ts in [0, 59, 86399, 951782400, 1709164800, 4102444800, -1, -951782400] {
    t.eq(dt.from_timestamp(ts).ts, ts)
    let d = dt.from_timestamp(ts)
    t.eq(dt.make(d.year, d.month, d.day, d.hour, d.minute, d.second).ts, ts)
  }
})

t.test("arithmetic", fn() {
  let d = dt.make(2026, 10, 3, 14, 30)
  t.eq(d.add_days(30).format("%Y-%m-%d"), "2026-11-02")
  t.eq(d.add_hours(10).format("%Y-%m-%d %H"), "2026-10-04 00")
  t.eq(d.add_months(4).format("%Y-%m-%d"), "2027-02-03")
  t.eq(d.add_years(1).add_months(2).format("%Y-%m-%d"), "2027-12-03")
  t.eq(dt.make(2024, 1, 31).add_months(1).format("%Y-%m-%d"), "2024-02-29")
  t.eq(dt.make(2025, 1, 31).add_months(1).format("%Y-%m-%d"), "2025-02-28")
  t.eq(dt.make(2026, 1, 15).add_months(-2).format("%Y-%m-%d"), "2025-11-15")
  t.eq(dt.make(2026, 1, 1).days_until(dt.make(2026, 12, 25)), 358)
  t.ok(dt.make(2026, 1, 1).is_before(dt.make(2026, 1, 2)))
  t.eq(d.start_of_day().format("%H:%M"), "00:00")
})

t.test("leap years and month lengths", fn() {
  t.ok(dt.is_leap(2000))
  t.ok(not dt.is_leap(1900))
  t.ok(dt.is_leap(2024))
  t.eq(dt.days_in_month(2024, 2), 29)
  t.eq(dt.days_in_month(2025, 2), 28)
  t.eq(dt.days_in_month(2025, 4), 30)
  t.eq(dt.make(2024, 12, 31).day_of_year(), 366)
})

t.test("parse", fn() {
  t.eq(dt.parse("2026-10-03").ts, dt.make(2026, 10, 3).ts)
  t.eq(dt.parse("2026-10-03 14:30").ts, dt.make(2026, 10, 3, 14, 30).ts)
  t.eq(dt.parse("2026-10-03T14:30:05Z").ts, dt.make(2026, 10, 3, 14, 30, 5).ts)
  t.throws(fn() { dt.parse("nope") }, "can't read a date")
  t.throws(fn() { dt.parse("2026-1x-03") }, "can't read a date")
  t.throws(fn() { dt.make(2026, 2, 30) }, "day out of range")
  t.throws(fn() { dt.make(2026, 13, 1) }, "month must be")
})

t.test("now", fn() {
  t.ok(dt.now().year >= 2026)
  t.ok(dt.today().hour == 0)
})

t.run()
