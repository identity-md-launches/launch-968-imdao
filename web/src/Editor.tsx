import { useEffect, useState } from "react";
import {
  categories,
  fieldLabels,
  blankFields,
  fromTemplate,
  type Draft,
  type Fields,
  type Template,
} from "./data";
import { Badge, Icon, Notice, PageIntro } from "./components";
import { deleteDraft, writeDraft } from "./storage";
type Props = {
  initial?: Draft;
  template?: Template;
  setDirty: (dirty: boolean) => void;
  onChange: (drafts: Draft[]) => void;
  navigate: (url: string, force?: boolean) => void;
};
export default function Editor({
  initial,
  template,
  setDirty,
  onChange,
  navigate,
}: Props) {
  const [fields, setFields] = useState<Fields>(() =>
    initial
      ? { ...initial }
      : template
        ? fromTemplate(template)
        : blankFields(),
  );
  const [savedFields, setSavedFields] = useState(() =>
    initial
      ? JSON.stringify(initial)
      : template
        ? ""
        : JSON.stringify(blankFields()),
  );
  const [id, setId] = useState(initial?.id);
  const [errors, setErrors] = useState<Partial<Record<keyof Fields, string>>>(
    {},
  );
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [preview, setPreview] = useState(false);
  const sourceTemplateId = initial?.sourceTemplateId ?? template?.id ?? null;
  const business =
    fields.category === "Earn" ||
    template?.business ||
    initial?.sourceTemplateId === "paid-newsletter";
  const dirty = JSON.stringify(fields) !== savedFields;
  useEffect(() => {
    setDirty(dirty);
    return () => setDirty(false);
  }, [dirty, setDirty]);
  function update(key: keyof Fields, value: string) {
    const next = { ...fields, [key]: value };
    setFields(next);
    setDirty(JSON.stringify(next) !== savedFields);
    setMessage("");
    setError("");
    setErrors((e) => ({ ...e, [key]: undefined }));
  }
  const mainKeys: (keyof Fields)[] = [
    "problem",
    "beneficiary",
    "firstStep",
    "operator",
    "budget",
    "unit",
    "success",
    "risks",
    "references",
  ];
  const previewKeys: (keyof Fields)[] = [
    "problem",
    "beneficiary",
    "firstStep",
    "operator",
    "budget",
    "unit",
    "success",
    "risks",
    ...(business ? (["customers", "costs", "reporting"] as const) : []),
    "references",
  ];
  const incomplete = previewKeys.filter(
    (k) => k !== "references" && !fields[k].trim(),
  );
  function save() {
    const next: Partial<Record<keyof Fields, string>> = {};
    for (const k of ["title", "problem", "firstStep"] as const)
      if (!fields[k].trim())
        next[k] =
          `Add ${k === "title" ? "a title" : k === "problem" ? "the problem or opportunity" : "a first step"} to save this draft.`;
    if (
      fields.budget.trim() &&
      (!/^\d+(\.\d+)?$/.test(fields.budget.trim()) ||
        !Number.isFinite(Number(fields.budget)))
    )
      next.budget =
        "Enter a nonnegative number, or leave the amount blank if not specified.";
    if (fields.budget.trim() && !fields.unit.trim())
      next.unit =
        "Name the asset or unit for this amount, or leave both budget fields blank.";
    setErrors(next);
    setMessage("");
    setError("");
    if (Object.keys(next).length) {
      setPreview(false);
      setTimeout(
        () => document.getElementById(`field-${Object.keys(next)[0]}`)?.focus(),
        0,
      );
      return;
    }
    try {
      const draft: Draft = {
        ...fields,
        id: id ?? `draft-${crypto.randomUUID()}`,
        sourceTemplateId,
        provenance: "local",
        updatedAt: new Date().toISOString(),
      };
      const saved = writeDraft(draft);
      setId(draft.id);
      setSavedFields(JSON.stringify(fields));
      setDirty(false);
      onChange(saved);
      setMessage(
        "Saved on this device only. This private draft has not been submitted.",
      );
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "Draft was not saved. Keep this page open and retry.",
      );
    }
  }
  function remove() {
    if (
      !id ||
      !window.confirm(
        "Delete this saved draft from this device? Any unsaved edits in this editor will also be discarded. This cannot be undone.",
      )
    )
      return;
    try {
      const next = deleteDraft(id);
      onChange(next);
      setDirty(false);
      navigate("#/drafts", true);
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Draft was not deleted. Retry.",
      );
    }
  }
  function field(key: keyof Fields, textarea = true) {
    const required = ["title", "problem", "firstStep"].includes(key);
    const hints: Partial<Record<keyof Fields, string>> = {
      operator:
        "Leave blank if no operator has been proposed. A draft does not appoint anyone.",
      budget:
        "A suggested amount, not an approved budget. Leave blank for “not specified”.",
      unit: "For example, the name of an asset or a unit of work. No conversion is implied.",
      success:
        template?.success ??
        "What observable result would tell you this worked?",
      customers: "Who might pay, and what evidence of demand would you seek?",
      costs: "What would delivery cost? Include time and any recurring costs.",
      reporting:
        "How would unused principal and any proceeds be recorded separately and reported?",
      references:
        "Optional source notes or URLs. Saved and displayed as plain text.",
    };
    const common = {
      id: `field-${key}`,
      name: key,
      value: fields[key],
      onChange: (
        e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
      ) => update(key, e.target.value),
      maxLength: key === "title" ? 160 : 5000,
      "aria-required": required,
      "aria-invalid": !!errors[key],
      "aria-describedby":
        `${hints[key] ? `hint-${key} ` : ""}${errors[key] ? `error-${key}` : ""}`.trim() ||
        undefined,
    };
    return (
      <div
        className={`form-field ${key === "title" ? "full-width" : ""}`}
        key={key}
      >
        <label htmlFor={`field-${key}`}>
          {fieldLabels[key]}
          {required && <span className="required-label">Required</span>}
        </label>
        {hints[key] && (
          <p className="field-hint" id={`hint-${key}`}>
            {hints[key]}
          </p>
        )}
        {textarea ? (
          <textarea
            {...common}
            rows={key === "problem" || key === "firstStep" ? 4 : 3}
          />
        ) : (
          <input
            {...common}
            type="text"
            inputMode={key === "budget" ? "decimal" : "text"}
            autoComplete="off"
          />
        )}
        {errors[key] && (
          <p className="field-error" id={`error-${key}`}>
            {errors[key]}
          </p>
        )}
      </div>
    );
  }
  return (
    <>
      <a className="back-link" href="#/drafts">
        ← Your local drafts
      </a>
      <PageIntro
        eyebrow="A private place to begin"
        title={initial ? "Keep shaping your idea." : "What could we try next?"}
      >
        <p>
          A little detail gives an idea somewhere to go. It doesn’t need every
          answer yet.
        </p>
      </PageIntro>
      <Notice>
        <strong>Saved on this device only.</strong> Nothing is shared, submitted
        or funded. Local drafts may be lost if browser data is cleared. Keep a
        separate copy of anything important.
      </Notice>
      <div className="editor-layout">
        <div className="surface editor">
          <div className="editor-toolbar">
            <div className="segmented">
              <button aria-pressed={!preview} onClick={() => setPreview(false)}>
                Edit draft
              </button>
              <button aria-pressed={preview} onClick={() => setPreview(true)}>
                Preview draft
              </button>
            </div>
            <Badge>
              {dirty ? "Unsaved changes" : id ? "Saved locally" : "New draft"}
            </Badge>
          </div>
          {preview ? (
            <section className="draft-preview">
              <p className="eyebrow">
                Private draft preview · {fields.category}
              </p>
              <h2>{fields.title.trim() || "Title not specified"}</h2>
              <p className="muted">
                {incomplete.length
                  ? `${incomplete.length} fields are not specified. This is an incomplete draft.`
                  : "This is a working draft, not a governance-ready proposal."}
              </p>
              <dl>
                {previewKeys.map((k) => (
                  <div key={k}>
                    <dt>{fieldLabels[k]}</dt>
                    <dd dir="auto">{fields[k].trim() || "Not specified"}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ) : (
            <form
              id="draft-form"
              noValidate
              onSubmit={(e) => {
                e.preventDefault();
                save();
              }}
            >
              <p className="small muted">
                Title, problem and first step are required to save. Other blank
                fields remain “Not specified”.
              </p>
              {field("title", false)}
              <div className="form-field">
                <label htmlFor="field-category">Category</label>
                <select
                  id="field-category"
                  name="category"
                  value={fields.category}
                  onChange={(e) => update("category", e.target.value)}
                >
                  {categories.map((c) => (
                    <option key={c}>{c}</option>
                  ))}
                </select>
              </div>
              {mainKeys.map((k) =>
                field(k, !["operator", "budget", "unit"].includes(k)),
              )}
              {business && (
                <fieldset>
                  <legend>Business experiment</legend>
                  <p className="muted">
                    A business idea needs demand, cost assumptions and a clear
                    reporting plan before a funding decision.
                  </p>
                  {(["customers", "costs", "reporting"] as const).map((k) =>
                    field(k),
                  )}
                </fieldset>
              )}
            </form>
          )}
          {error && <Notice error>{error}</Notice>}
          <p className="save-message" role="status">
            {message}
          </p>
          <div className="editor-actions">
            <button className="button primary" onClick={save}>
              Save draft <Icon size={18} />
            </button>
            {id && (
              <button className="button danger" onClick={remove}>
                Delete draft
              </button>
            )}
          </div>
        </div>
        <aside className="draft-aside">
          <span className="icon-tile">
            <Icon name="Experiment" size={24} />
          </span>
          <h2>
            Start small.
            <br />
            Leave room to learn.
          </h2>
          <p>A clear first step is more useful than a perfect plan.</p>
          <dl>
            <dt>Origin</dt>
            <dd>
              {sourceTemplateId
                ? `Starter: ${template?.title ?? sourceTemplateId}`
                : "Started from scratch"}
            </dd>
            <dt>Provenance</dt>
            <dd>Private, local draft</dd>
            <dt>Next step</dt>
            <dd>
              Refine the idea. A saved draft is not a formal governance
              proposal.
            </dd>
          </dl>
          <a className="text-link" href="#/draft/new">
            Start a fresh draft <Icon name="plus" size={17} />
          </a>
          <a className="text-link" href="#/ideas">
            Browse the starters <Icon size={17} />
          </a>
        </aside>
      </div>
    </>
  );
}
