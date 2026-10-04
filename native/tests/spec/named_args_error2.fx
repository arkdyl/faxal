# compile-error: Named arguments aren't supported after '|>'
fn f(a, b = 1) => a
print(1 |> f(b = 2))
