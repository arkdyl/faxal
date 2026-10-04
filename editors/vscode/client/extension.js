// The Faxal extension: syntax colors (from the grammar) plus the language server, which is the
// `faxal lsp` command. VS Code talks to it through the standard vscode-languageclient library.
const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

function activate(context) {
  const config = vscode.workspace.getConfiguration("faxal");
  const command = config.get("path") || "faxal";
  const serverOptions = {
    run: { command, args: ["lsp"], transport: TransportKind.stdio },
    debug: { command, args: ["lsp"], transport: TransportKind.stdio },
  };
  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "faxal" }, { scheme: "untitled", language: "faxal" }],
    synchronize: { fileEvents: vscode.workspace.createFileSystemWatcher("**/*.fx") },
  };
  client = new LanguageClient("faxal", "Faxal Language Server", serverOptions, clientOptions);
  client.start().catch((err) => {
    vscode.window.showErrorMessage(
      `Faxal: could not start "${command} lsp" (${err.message}). Install faxal, or set "faxal.path" in the settings.`,
    );
  });
  context.subscriptions.push(
    vscode.commands.registerCommand("faxal.restartServer", async () => {
      if (client) await client.stop();
      await client.start();
    }),
    vscode.commands.registerCommand("faxal.runFile", () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      editor.document.save().then(() => {
        const terminal = vscode.window.createTerminal("Faxal");
        terminal.show();
        terminal.sendText(`${JSON.stringify(command)} ${JSON.stringify(editor.document.fileName)}`);
      });
    }),
  );
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
