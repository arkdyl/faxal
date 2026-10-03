# cli-only
# A command-line program: faxal examples/cli_tool.fx Ada Grace
# (Make it a standalone app with: faxal build examples/cli_tool.fx -o greeter)
let names = os.args.len() > 0 and os.args or ["world"]
for name in names {
  print(f"Hello, {name}!")
}
