export interface Snippet {
  id: string;
  title: string;
  code: string;
  public: boolean;
  views: number;
  createdAt: number;
  preview: { background: string | null; segments: [number, number, number, number, string, number][]; shapes?: any[] } | null;
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(url, init);
  } catch {
    throw new Error("Can't reach the server. Is it running?");
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error ?? `Request failed (${res.status})`);
  return body as T;
}

export const getSnippet = (id: string) => request<Snippet>(`/api/snippets/${id}`);

export const getGallery = () => request<{ snippets: Snippet[] }>("/api/gallery").then((r) => r.snippets);

export const createSnippet = (data: { code: string; title: string; public: boolean }) =>
  request<{ id: string }>("/api/snippets", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(data),
  });
