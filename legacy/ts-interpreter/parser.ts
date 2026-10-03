import { FaxalError, Token, lex } from "./lexer";

export type Expr =
  | { kind: "num"; value: number }
  | { kind: "str"; value: string }
  | { kind: "bool"; value: boolean }
  | { kind: "nil" }
  | { kind: "var"; name: string; line: number; col: number }
  | { kind: "list"; items: Expr[] }
  | { kind: "dict"; entries: { key: Expr; value: Expr }[] }
  | { kind: "index"; obj: Expr; index: Expr; line: number; col: number }
  | { kind: "unary"; op: string; expr: Expr }
  | { kind: "binary"; op: string; left: Expr; right: Expr; line: number; col: number }
  | { kind: "assign"; target: Expr; value: Expr; line: number; col: number }
  | { kind: "call"; callee: Expr; args: Expr[]; line: number; col: number }
  | { kind: "fn"; params: string[]; body: Stmt[] };

export type Stmt =
  | { kind: "let"; name: string; value: Expr }
  | { kind: "expr"; expr: Expr }
  | { kind: "if"; cond: Expr; then: Stmt[]; else_?: Stmt[] }
  | { kind: "while"; cond: Expr; body: Stmt[] }
  | { kind: "for"; name: string; iter: Expr; body: Stmt[]; line: number; col: number }
  | { kind: "break" }
  | { kind: "continue" }
  | { kind: "return"; value?: Expr };

export function parse(src: string): Stmt[] {
  const tokens = lex(src);
  let p = 0;

  const peek = () => tokens[p];
  const next = () => tokens[p++];
  const is = (type: string, value?: string) =>
    peek().type === type && (value === undefined || peek().value === value);
  const eat = (type: string, value?: string): Token | null =>
    is(type, value) ? next() : null;
  const expect = (type: string, value?: string): Token => {
    if (is(type, value)) return next();
    const t = peek();
    throw new FaxalError(`Expected '${value ?? type}' but found '${t.value || t.type}'`, t.line, t.col);
  };

  function block(): Stmt[] {
    expect("punct", "{");
    const body: Stmt[] = [];
    while (!is("punct", "}") && !is("eof")) body.push(statement());
    expect("punct", "}");
    return body;
  }

  function statement(): Stmt {
    if (eat("keyword", "let")) {
      const name = expect("ident").value;
      expect("op", "=");
      const value = expression();
      eat("punct", ";");
      return { kind: "let", name, value };
    }
    if (eat("keyword", "if")) {
      const cond = expression();
      const then = block();
      let else_: Stmt[] | undefined;
      if (eat("keyword", "else")) {
        else_ = is("keyword", "if") ? [statement()] : block();
      }
      return { kind: "if", cond, then, else_ };
    }
    if (eat("keyword", "while")) {
      const cond = expression();
      return { kind: "while", cond, body: block() };
    }
    if (is("keyword", "for")) {
      const f = next();
      const name = expect("ident").value;
      expect("keyword", "in");
      const iter = expression();
      return { kind: "for", name, iter, body: block(), line: f.line, col: f.col };
    }
    if (eat("keyword", "break")) { eat("punct", ";"); return { kind: "break" }; }
    if (eat("keyword", "continue")) { eat("punct", ";"); return { kind: "continue" }; }
    if (eat("keyword", "return")) {
      const value = is("punct", ";") || is("punct", "}") ? undefined : expression();
      eat("punct", ";");
      return { kind: "return", value };
    }
    const expr = expression();
    eat("punct", ";");
    return { kind: "expr", expr };
  }

  function expression(): Expr {
    return assignment();
  }

  function assignment(): Expr {
    const left = or();
    if (is("op", "=")) {
      const eq = next();
      if (left.kind !== "var" && left.kind !== "index") {
        throw new FaxalError("Invalid assignment target", eq.line, eq.col);
      }
      return { kind: "assign", target: left, value: assignment(), line: eq.line, col: eq.col };
    }
    return left;
  }

  const binaryLevel = (
    ops: { type: string; values: string[] },
    sub: () => Expr,
  ) => (): Expr => {
    let left = sub();
    while (peek().type === ops.type && ops.values.includes(peek().value)) {
      const t = next();
      left = { kind: "binary", op: t.value, left, right: sub(), line: t.line, col: t.col };
    }
    return left;
  };

  const or: () => Expr = binaryLevel({ type: "keyword", values: ["or"] }, () => and());
  const and: () => Expr = binaryLevel({ type: "keyword", values: ["and"] }, () => equality());
  const equality: () => Expr = binaryLevel({ type: "op", values: ["==", "!="] }, () => comparison());
  const comparison: () => Expr = binaryLevel({ type: "op", values: ["<", ">", "<=", ">="] }, () => term());
  const term: () => Expr = binaryLevel({ type: "op", values: ["+", "-"] }, () => factor());
  const factor: () => Expr = binaryLevel({ type: "op", values: ["*", "/", "%"] }, () => unary());

  function unary(): Expr {
    if (is("op", "-") || is("keyword", "not")) {
      const op = next().value;
      return { kind: "unary", op, expr: unary() };
    }
    return postfix();
  }

  function postfix(): Expr {
    let expr = primary();
    for (;;) {
      if (is("punct", "(")) {
        const open = next();
        const args: Expr[] = [];
        if (!is("punct", ")")) {
          do { args.push(expression()); } while (eat("punct", ","));
        }
        expect("punct", ")");
        expr = { kind: "call", callee: expr, args, line: open.line, col: open.col };
      } else if (is("punct", "[")) {
        const open = next();
        const index = expression();
        expect("punct", "]");
        expr = { kind: "index", obj: expr, index, line: open.line, col: open.col };
      } else {
        return expr;
      }
    }
  }

  function primary(): Expr {
    const t = peek();
    if (eat("number")) return { kind: "num", value: parseFloat(t.value) };
    if (eat("string")) return { kind: "str", value: t.value };
    if (eat("keyword", "true")) return { kind: "bool", value: true };
    if (eat("keyword", "false")) return { kind: "bool", value: false };
    if (eat("keyword", "nil")) return { kind: "nil" };
    if (eat("ident")) return { kind: "var", name: t.value, line: t.line, col: t.col };
    if (eat("punct", "[")) {
      const items: Expr[] = [];
      if (!is("punct", "]")) {
        do {
          if (is("punct", "]")) break;
          items.push(expression());
        } while (eat("punct", ","));
      }
      expect("punct", "]");
      return { kind: "list", items };
    }
    if (eat("punct", "{")) {
      const entries: { key: Expr; value: Expr }[] = [];
      if (!is("punct", "}")) {
        do {
          if (is("punct", "}")) break;
          // a bare word like  name: 1  is shorthand for  "name": 1
          const key: Expr = is("ident") && tokens[p + 1].value === ":"
            ? { kind: "str", value: next().value }
            : expression();
          expect("punct", ":");
          entries.push({ key, value: expression() });
        } while (eat("punct", ","));
      }
      expect("punct", "}");
      return { kind: "dict", entries };
    }
    if (eat("keyword", "fn")) {
      expect("punct", "(");
      const params: string[] = [];
      if (!is("punct", ")")) {
        do { params.push(expect("ident").value); } while (eat("punct", ","));
      }
      expect("punct", ")");
      return { kind: "fn", params, body: block() };
    }
    if (eat("punct", "(")) {
      const e = expression();
      expect("punct", ")");
      return e;
    }
    throw new FaxalError(`Unexpected '${t.value || t.type}'`, t.line, t.col);
  }

  const program: Stmt[] = [];
  while (!is("eof")) program.push(statement());
  return program;
}
