import { highlight } from "./highlight";

export interface Editor {
  getValue(): string;
  setValue(v: string): void;
  setErrorLine(line: number | null): void;
  focus(): void;
}

interface Options {
  value: string;
  onRun?: () => void;
  onInput?: () => void;
  readOnly?: boolean;
}

/** A lightweight code editor: a transparent <textarea> on top of a highlighted <pre>. */
export function createEditor(parent: HTMLElement, opts: Options): Editor {
  parent.classList.add("editor");
  parent.innerHTML = `
    <div class="gutter" aria-hidden="true"><div class="gutter-inner"></div></div>
    <div class="code">
      <pre class="hl" aria-hidden="true"></pre>
      <textarea spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="off" aria-label="Faxal code"></textarea>
    </div>`;

  const gutterInner = parent.querySelector<HTMLElement>(".gutter-inner")!;
  const hl = parent.querySelector<HTMLElement>(".hl")!;
  const ta = parent.querySelector<HTMLTextAreaElement>("textarea")!;
  ta.value = opts.value;
  ta.readOnly = !!opts.readOnly;
  let errorLine: number | null = null;

  function render() {
    hl.innerHTML = highlight(ta.value) + "\n";
    const n = ta.value.split("\n").length;
    let nums = "";
    for (let i = 1; i <= n; i++) nums += i === errorLine ? `<span class="err">${i}</span>\n` : `${i}\n`;
    gutterInner.innerHTML = nums;
  }

  function syncScroll() {
    hl.scrollTop = ta.scrollTop;
    hl.scrollLeft = ta.scrollLeft;
    gutterInner.style.transform = `translateY(${-ta.scrollTop}px)`;
  }

  function insert(text: string) {
    ta.focus();
    // execCommand keeps the browser's undo stack intact
    if (!document.execCommand("insertText", false, text)) {
      ta.setRangeText(text, ta.selectionStart, ta.selectionEnd, "end");
      ta.dispatchEvent(new Event("input"));
    }
  }

  ta.addEventListener("input", () => { errorLine = null; render(); syncScroll(); opts.onInput?.(); });
  ta.addEventListener("scroll", syncScroll);
  ta.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
      e.preventDefault();
      opts.onRun?.();
    } else if (e.key === "Tab" && !e.shiftKey) {
      e.preventDefault();
      insert("  ");
    } else if (e.key === "Enter" && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
      const pos = ta.selectionStart;
      const lineStart = ta.value.lastIndexOf("\n", pos - 1) + 1;
      const indent = /^[ \t]*/.exec(ta.value.slice(lineStart, pos))![0];
      const before = ta.value[pos - 1];
      const after = ta.value[ta.selectionEnd];
      if (before === "{") {
        e.preventDefault();
        if (after === "}") {
          insert("\n" + indent + "  \n" + indent);
          ta.selectionStart = ta.selectionEnd = pos + indent.length + 3;
        } else {
          insert("\n" + indent + "  ");
        }
      } else if (indent) {
        e.preventDefault();
        insert("\n" + indent);
      }
    }
  });

  render();
  return {
    getValue: () => ta.value,
    setValue(v) { ta.value = v; errorLine = null; render(); ta.scrollTop = 0; syncScroll(); },
    setErrorLine(line) { errorLine = line; render(); },
    focus: () => ta.focus(),
  };
}
