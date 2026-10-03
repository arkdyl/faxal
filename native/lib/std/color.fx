# std/color: colors for drawing, written in Faxal.
# Every function returns a color you can pass to color() or background().

fn rgb(r, g, b) {
  return f"rgb({round(r)}, {round(g)}, {round(b)})"
}

# hue 0-360, saturation and lightness 0-100
fn hsl(h, s = 70, l = 50) {
  return f"hsl({round(h) % 360}, {round(s)}%, {round(l)}%)"
}

# gray(0) is black and gray(1) is white
fn gray(amount) {
  let v = round(math.clamp(amount, 0, 1) * 255)
  return rgb(v, v, v)
}

# Spreads n colors around the color wheel: rainbow(2, 6) is the third of six.
fn rainbow(i, n, s = 80, l = 55) {
  return hsl(360 * i / n, s, l)
}
