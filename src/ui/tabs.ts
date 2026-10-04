/**
 * Makes a row of buttons with role="tab" work from the keyboard: arrow keys, Home and End move between the tabs
 * (and activate them), and only the selected tab can be reached with Tab. Call again after the tabs are redrawn.
 */
export function enableTabKeys(list: HTMLElement) {
  const tabs = () => Array.from(list.querySelectorAll<HTMLElement>('[role="tab"]'));
  const sync = () => tabs().forEach((t) => t.setAttribute("tabindex", t.getAttribute("aria-selected") === "true" ? "0" : "-1"));
  sync();
  list.addEventListener("keydown", (e) => {
    const all = tabs();
    const at = all.indexOf(document.activeElement as HTMLElement);
    if (at < 0) return;
    let next = -1;
    if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (at + 1) % all.length;
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (at - 1 + all.length) % all.length;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = all.length - 1;
    if (next < 0) return;
    e.preventDefault();
    all[next].click();           // the page's own click handler selects it (some pages redraw their tabs)...
    const chosen = list.isConnected ? list : document;
    const now = chosen.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]');
    if (now) {
      Array.from(now.parentElement!.querySelectorAll<HTMLElement>('[role="tab"]')).forEach((t) => t.setAttribute("tabindex", t === now ? "0" : "-1"));
      now.focus();               // ...and the focus follows
    }
  });
  list.addEventListener("click", () => queueMicrotask(sync));
}
