// The examples are real .fx files in /examples, shared with the command-line tool.
const files = import.meta.glob("../examples/*.fx", { query: "?raw", import: "default", eager: true }) as Record<string, string>;

export interface Example { id: string; title: string; code: string }

const ORDER = ["hello", "spiral", "rosette", "star", "tree", "snowflake", "mandala", "shapes", "lists", "fib", "closures", "named_args", "classes", "types", "generators", "async_tasks", "regex_dates", "pipes", "stdlib", "errors"];

export const EXAMPLES: Example[] = Object.entries(files)
  .filter(([, code]) => !code.includes("# cli-only"))
  .map(([path, code]) => {
    const id = path.split("/").pop()!.replace(/\.fx$/, "");
    const title = /^# title: (.*)$/m.exec(code)?.[1] ?? id;
    return { id, title, code: code.replace(/^# title: .*\n/, "") };
  })
  .sort((a, b) => ORDER.indexOf(a.id) - ORDER.indexOf(b.id));

export const byId = (id: string) => EXAMPLES.find((e) => e.id === id);
