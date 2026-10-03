const KEYWORDS = new Set([
  "let", "fn", "if", "else", "while", "for", "in", "break", "continue", "return",
  "true", "false", "nil", "and", "or", "not", "try", "catch", "throw", "import", "class", "extends", "self", "super", "by", "async", "await",
]);
const BUILTINS = new Set([
  "print", "write", "isinstance", "input", "len", "str", "repr", "num", "int", "type", "range", "assert", "ord", "chr",
  "abs", "floor", "ceil", "round", "sqrt", "min", "max", "math", "json", "fs", "os", "time",
  "forward", "back", "turn", "penup", "pendown", "width", "goto", "home", "color", "background", "save_svg", "circle", "disc", "rect", "box", "text",
]);

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const TOKEN = /(#[^\n]*)|(f?"(?:\\.|[^"\\])*"?|f?'(?:\\.|[^'\\])*'?)|(\d+(?:\.\d+)?)|([A-Za-z_]\w*)|([\s\S])/g;

/** Turns Faxal source into HTML with <span class="t-…"> wrappers. Output is escaped. */
export function highlight(code: string): string {
  let out = "";
  for (const m of code.matchAll(TOKEN)) {
    const [text, comment, string, number, word] = m;
    if (comment) out += `<span class="t-c">${esc(text)}</span>`;
    else if (string) out += `<span class="t-s">${esc(text)}</span>`;
    else if (number) out += `<span class="t-n">${text}</span>`;
    else if (word && KEYWORDS.has(word)) out += `<span class="t-k">${text}</span>`;
    else if (word && BUILTINS.has(word)) out += `<span class="t-b">${text}</span>`;
    else out += esc(text);
  }
  return out;
}
