# Faxal for VS Code

Syntax highlighting and the Faxal language server (`faxal lsp`):

- errors as you type, checked by the real compiler
- completion, hover help, signature help while you type arguments
- go to definition (across `import`ed files), find references, rename
- format document (the same formatter as `faxal fmt`)
- an outline of functions, classes and variables; symbol search
- the commands "Faxal: Run this file" and "Faxal: Restart the language server"

You need the `faxal` program on your PATH (see https://github.com/arkdyl/faxal), or set `faxal.path` in the settings.

## Install it

From a checkout of the repository:

```bash
cd editors/vscode
npm install                       # fetches vscode-languageclient
npx @vscode/vsce package          # makes faxal-1.1.0.vsix
code --install-extension faxal-1.1.0.vsix
```

Or, without packaging, copy this folder to `~/.vscode/extensions/faxal` (after `npm install`) and restart VS Code.

Other editors (Neovim, Helix, Zed, Emacs, Sublime) can use `faxal lsp` directly: tell them to run that command for `.fx` files.
