export type TokenType =
  | "number" | "string" | "ident" | "keyword" | "op" | "punct" | "eof";

export interface Token {
  type: TokenType;
  value: string;
  line: number;
  col: number;
}

export class FaxalError extends Error {
  constructor(message: string, public line: number, public col: number) {
    super(`${message} (line ${line}, col ${col})`);
  }
}

const KEYWORDS = new Set([
  "let", "fn", "if", "else", "while", "for", "in", "break", "continue", "return",
  "true", "false", "nil", "and", "or", "not",
]);

const TWO_CHAR_OPS = new Set(["==", "!=", "<=", ">="]);
const ONE_CHAR_OPS = new Set(["+", "-", "*", "/", "%", "<", ">", "="]);
const PUNCT = new Set(["(", ")", "{", "}", "[", "]", ",", ";", ":"]);

export function lex(src: string): Token[] {
  const tokens: Token[] = [];
  let i = 0, line = 1, col = 1;

  const advance = () => {
    if (src[i] === "\n") { line++; col = 1; } else { col++; }
    i++;
  };
  const push = (type: TokenType, value: string, l: number, c: number) =>
    tokens.push({ type, value, line: l, col: c });

  while (i < src.length) {
    const ch = src[i];
    const l = line, c = col;

    if (/\s/.test(ch)) { advance(); continue; }

    // comments: # to end of line
    if (ch === "#") {
      while (i < src.length && src[i] !== "\n") advance();
      continue;
    }

    if (/[0-9]/.test(ch)) {
      let s = "";
      while (i < src.length && /[0-9.]/.test(src[i])) { s += src[i]; advance(); }
      push("number", s, l, c);
      continue;
    }

    if (/[A-Za-z_]/.test(ch)) {
      let s = "";
      while (i < src.length && /[A-Za-z0-9_]/.test(src[i])) { s += src[i]; advance(); }
      push(KEYWORDS.has(s) ? "keyword" : "ident", s, l, c);
      continue;
    }

    if (ch === '"') {
      advance();
      let s = "";
      while (i < src.length && src[i] !== '"') {
        if (src[i] === "\\" && i + 1 < src.length) {
          advance();
          s += src[i] === "n" ? "\n" : src[i];
        } else {
          s += src[i];
        }
        advance();
      }
      if (i >= src.length) throw new FaxalError("Unterminated string", l, c);
      advance();
      push("string", s, l, c);
      continue;
    }

    const two = src.slice(i, i + 2);
    if (TWO_CHAR_OPS.has(two)) { advance(); advance(); push("op", two, l, c); continue; }
    if (ONE_CHAR_OPS.has(ch)) { advance(); push("op", ch, l, c); continue; }
    if (PUNCT.has(ch)) { advance(); push("punct", ch, l, c); continue; }

    throw new FaxalError(`Unexpected character '${ch}'`, l, c);
  }

  push("eof", "", line, col);
  return tokens;
}
