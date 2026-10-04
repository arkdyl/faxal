# page.fx: the web page of the notes app (one HTML file with a little JavaScript).

let HTML = "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Notes · written in Faxal</title>
<style>
  :root { --fg: #0d0e10; --muted: #6b6d74; --line: #e6e6e9; --soft: #f6f6f7; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 17px/1.5 Inter, system-ui, sans-serif; color: var(--fg); }
  main { max-width: 720px; margin: 0 auto; padding: 48px 20px 96px; }
  h1 { font-size: 40px; letter-spacing: -0.04em; margin: 0 0 4px; }
  .sub { color: var(--muted); margin: 0 0 32px; }
  form { display: grid; gap: 10px; margin-bottom: 28px; }
  textarea, input { font: inherit; padding: 12px 14px; border: 2px solid var(--line); border-radius: 14px; width: 100%; }
  textarea:focus, input:focus { outline: none; border-color: var(--fg); }
  button { font: 600 16px inherit; border: 0; border-radius: 999px; padding: 12px 22px; background: var(--fg); color: #fff; cursor: pointer; justify-self: start; }
  button.soft { background: var(--soft); color: var(--fg); padding: 6px 14px; font-size: 14px; }
  .note { padding: 18px 20px; border-radius: 18px; background: var(--soft); margin-bottom: 12px; }
  .note p { margin: 0 0 10px; white-space: pre-wrap; }
  .meta { color: var(--muted); font-size: 14px; display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .tag { background: #fff; border-radius: 999px; padding: 2px 10px; cursor: pointer; }
  .bar { display: flex; gap: 10px; margin-bottom: 20px; }
</style>
</head>
<body>
<main>
  <h1>Notes</h1>
  <p class=\"sub\">A web app written entirely in <a href=\"https://github.com/arkdyl/faxal\">Faxal</a>: this page is served by Faxal, and so is the API behind it.</p>
  <form id=\"add\">
    <textarea id=\"text\" rows=\"3\" placeholder=\"Write a note...\" required></textarea>
    <input id=\"tags\" placeholder=\"tags, separated by commas (optional)\">
    <button>Add note</button>
  </form>
  <div class=\"bar\"><input id=\"search\" placeholder=\"Search...\"><button class=\"soft\" id=\"clear\">All</button></div>
  <div id=\"notes\"></div>
</main>
<script>
const $ = (s) => document.querySelector(s);
let tag = null;
const esc = (s) => s.replace(/[&<>\"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));
async function load() {
  const q = encodeURIComponent($('#search').value), t = tag ? '&tag=' + encodeURIComponent(tag) : '';
  const notes = await (await fetch('/api/notes?q=' + q + t)).json();
  $('#notes').innerHTML = notes.length ? notes.map((n) => `
    <div class=\"note\"><p>${esc(n.text)}</p>
      <div class=\"meta\">${n.tags.map((x) => `<span class=\"tag\" data-tag=\"${esc(x)}\">#${esc(x)}</span>`).join('')}
        <span>${n.created.slice(0, 10)}</span><button class=\"soft\" data-del=\"${n.id}\">Delete</button></div></div>`).join('')
    : '<p class=\"sub\">No notes yet.</p>';
}
$('#add').addEventListener('submit', async (e) => {
  e.preventDefault();
  const tags = $('#tags').value.split(',').map((s) => s.trim()).filter(Boolean);
  await fetch('/api/notes', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({text: $('#text').value, tags})});
  $('#text').value = ''; $('#tags').value = ''; load();
});
$('#search').addEventListener('input', load);
$('#clear').addEventListener('click', () => { tag = null; $('#search').value = ''; load(); });
$('#notes').addEventListener('click', async (e) => {
  if (e.target.dataset.tag) { tag = e.target.dataset.tag; load(); }
  if (e.target.dataset.del) { await fetch('/api/notes/' + e.target.dataset.del, {method: 'DELETE'}); load(); }
});
load();
</script>
</body>
</html>
"
