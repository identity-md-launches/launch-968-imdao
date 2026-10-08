import {
  blankFields,
  categories,
  templates,
  type Draft,
  type Fields,
} from "./data";
export const DRAFT_KEY = "imdao.drafts.v1";
export const THEME_KEY = "imdao.theme.v1";
export type DraftLoad = { drafts: Draft[]; error: string | null };
const validId = (x: unknown): x is string =>
  typeof x === "string" && /^draft-[a-zA-Z0-9-]{1,80}$/.test(x);
function isDraft(x: unknown): x is Draft {
  if (!x || typeof x !== "object") return false;
  const d = x as Record<string, unknown>;
  return (
    validId(d.id) &&
    d.provenance === "local" &&
    typeof d.updatedAt === "string" &&
    Number.isFinite(Date.parse(d.updatedAt)) &&
    (d.sourceTemplateId === null ||
      templates.some((t) => t.id === d.sourceTemplateId)) &&
    Object.keys(blankFields()).every(
      (k) =>
        typeof d[k] === "string" &&
        (d[k] as string).length <= (k === "title" ? 160 : 5000),
    ) &&
    categories.includes(d.category as Fields["category"]) &&
    (!(d.budget as string).trim() ||
      (/^\d+(\.\d+)?$/.test((d.budget as string).trim()) &&
        Number.isFinite(Number(d.budget)) &&
        (d.unit as string).trim().length > 0)) &&
    ["title", "problem", "firstStep"].every(
      (k) => (d[k] as string).trim().length > 0,
    )
  );
}
export function loadDrafts(): DraftLoad {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (raw === null) return { drafts: [], error: null };
    if (raw.length > 2000000) throw new Error("large");
    const data: unknown = JSON.parse(raw);
    if (
      !data ||
      typeof data !== "object" ||
      !("version" in data) ||
      data.version !== 1 ||
      !("drafts" in data) ||
      !Array.isArray(data.drafts) ||
      data.drafts.length > 60 ||
      !data.drafts.every(isDraft) ||
      new Set(data.drafts.map((d) => d.id)).size !== data.drafts.length
    )
      throw new Error("invalid");
    return { drafts: data.drafts, error: null };
  } catch {
    return {
      drafts: [],
      error:
        "Saved drafts could not be read. Storage may be blocked or the saved data may be damaged. Existing data has not been replaced. Retry, or explicitly reset local drafts.",
    };
  }
}
export function writeDraft(draft: Draft): Draft[] {
  if (!isDraft(draft))
    throw new Error(
      "This draft contains invalid fields. Check the required fields and try again.",
    );
  const current = loadDrafts();
  if (current.error) throw new Error(current.error);
  const drafts = [draft, ...current.drafts.filter((d) => d.id !== draft.id)];
  if (drafts.length > 60)
    throw new Error(
      "This device has 60 drafts. Delete an unneeded draft before saving another.",
    );
  const serialized = JSON.stringify({ version: 1, drafts });
  if (serialized.length > 2000000)
    throw new Error(
      "Drafts exceed the local size limit. Shorten a draft or delete an unneeded draft before saving.",
    );
  try {
    localStorage.setItem(DRAFT_KEY, serialized);
  } catch {
    throw new Error(
      "Draft was not saved. Device storage is unavailable or full. Keep this page open, copy your text, then free storage and retry.",
    );
  }
  return drafts;
}
export function deleteDraft(id: string): Draft[] {
  const current = loadDrafts();
  if (current.error) throw new Error(current.error);
  const drafts = current.drafts.filter((d) => d.id !== id);
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({ version: 1, drafts }));
  } catch {
    throw new Error(
      "Draft was not deleted. Device storage is unavailable. Retry when storage is available.",
    );
  }
  return drafts;
}
