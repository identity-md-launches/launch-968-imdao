import { useCallback, useEffect, useRef, useState } from "react";
import Editor from "./Editor";
import { templates, type Draft } from "./data";
import { DRAFT_KEY, THEME_KEY, deleteDraft, loadDrafts } from "./storage";
import { Badge, Icon, Logo, Missing, Notice, PageIntro } from "./components";
import {
  IdeaDetail,
  IdeasPage,
  ProjectDetail,
  ProjectsPage,
  TreasuryPage,
  VoteDetail,
  VotePage,
} from "./pages";
export default function App() {
  const [route, setRoute] = useState(location.hash || "#/");
  const [revision, setRevision] = useState(0);
  const routeRef = useRef(route);
  const dirtyRef = useRef(false);
  const acceptedHash = useRef("");
  const [theme, setTheme] = useState(
    document.documentElement.dataset.theme === "dark" ? "dark" : "light",
  );
  const [themeError, setThemeError] = useState("");
  const manualTheme = useRef(false);
  const [draftState, setDraftState] = useState(loadDrafts);
  const [draftNotice, setDraftNotice] = useState("");
  const setDirty = useCallback((value: boolean) => {
    dirtyRef.current = value;
  }, []);
  const navigate = useCallback((url: string, force = false) => {
    if (
      !force &&
      dirtyRef.current &&
      !window.confirm(
        "Discard unsaved changes and leave this draft? Saved versions will stay on this device.",
      )
    )
      return;
    dirtyRef.current = false;
    if (url === location.hash) {
      setRevision((n) => n + 1);
      return;
    }
    acceptedHash.current = url;
    location.hash = url;
  }, []);
  useEffect(() => {
    const hash = () => {
      const next = location.hash || "#/";
      if (
        acceptedHash.current !== next &&
        dirtyRef.current &&
        !window.confirm(
          "Discard unsaved changes and leave this draft? Saved versions will stay on this device.",
        )
      ) {
        history.replaceState(null, "", routeRef.current);
        return;
      }
      acceptedHash.current = "";
      dirtyRef.current = false;
      routeRef.current = next;
      setRoute(next);
    };
    const click = (e: MouseEvent) => {
      const link = e.target instanceof Element ? e.target.closest("a") : null;
      const href = link?.getAttribute("href");
      if (
        !href?.startsWith("#/") ||
        e.defaultPrevented ||
        e.button !== 0 ||
        e.ctrlKey ||
        e.metaKey ||
        e.shiftKey ||
        e.altKey
      )
        return;
      e.preventDefault();
      if (href === routeRef.current && !href.startsWith("#/draft/")) return;
      navigate(href);
    };
    const unload = (e: BeforeUnloadEvent) => {
      if (dirtyRef.current) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    const storage = (e: StorageEvent) => {
      if (e.key === DRAFT_KEY || e.key === null) setDraftState(loadDrafts());
    };
    window.addEventListener("hashchange", hash);
    document.addEventListener("click", click);
    window.addEventListener("beforeunload", unload);
    window.addEventListener("storage", storage);
    return () => {
      window.removeEventListener("hashchange", hash);
      document.removeEventListener("click", click);
      window.removeEventListener("beforeunload", unload);
      window.removeEventListener("storage", storage);
    };
  }, [navigate]);
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      document.querySelector<HTMLElement>("h1")?.focus({ preventScroll: true });
      window.scrollTo(0, 0);
    });
    return () => cancelAnimationFrame(frame);
  }, [route, revision]);
  useEffect(() => {
    try {
      manualTheme.current = ["light", "dark"].includes(
        localStorage.getItem(THEME_KEY) ?? "",
      );
    } catch {
      /* session theme still works */
    }
    const media = matchMedia("(prefers-color-scheme: dark)");
    const change = () => {
      if (!manualTheme.current) setTheme(media.matches ? "dark" : "light");
    };
    media.addEventListener("change", change);
    return () => media.removeEventListener("change", change);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute("content", theme === "dark" ? "#171b1d" : "#edf1e9");
  }, [theme]);
  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    manualTheme.current = true;
    setTheme(next);
    try {
      localStorage.setItem(THEME_KEY, next);
      setThemeError("");
    } catch {
      setThemeError(
        "Theme changed for this session. This browser could not remember your preference.",
      );
    }
  }
  function changed(drafts: Draft[]) {
    setDraftState({ drafts, error: null });
  }
  function removeDraft(id: string) {
    if (!window.confirm("Delete this local draft? This cannot be undone."))
      return;
    try {
      changed(deleteDraft(id));
      setDraftNotice("Draft deleted from this device.");
    } catch (e) {
      setDraftNotice("");
      setDraftState((s) => ({
        ...s,
        error: e instanceof Error ? e.message : "Draft was not deleted. Retry.",
      }));
    }
  }
  function resetDrafts() {
    if (
      !window.confirm(
        "Reset all local drafts? This permanently removes saved draft data from this device, including unreadable data.",
      )
    )
      return;
    try {
      localStorage.removeItem(DRAFT_KEY);
      setDraftState(loadDrafts());
      setDraftNotice("Local draft storage reset.");
    } catch {
      setDraftNotice("");
      setDraftState((s) => ({
        ...s,
        error:
          "Storage is still unavailable. Drafts were not reset. Allow browser storage and retry.",
      }));
    }
  }
  const [path, query = ""] = route.replace(/^#/, "").split("?");
  const parts = path.split("/").filter(Boolean);
  const section = parts[0] ?? "";
  const id = parts[1];
  const editorTemplateId = new URLSearchParams(query).get("template");
  const template = templates.find((t) => t.id === editorTemplateId);
  const initialDraft = draftState.drafts.find((d) => d.id === id);
  let page;
  if (parts.length > 2) page = <Missing />;
  else if (section === "" || (section === "ideas" && !id))
    page = <IdeasPage key={section} home={!section} />;
  else if (section === "ideas" && id) page = <IdeaDetail id={id} />;
  else if (section === "projects")
    page = id ? <ProjectDetail id={id} /> : <ProjectsPage />;
  else if (section === "vote")
    page = id ? <VoteDetail id={id} /> : <VotePage />;
  else if (section === "treasury" && !id) page = <TreasuryPage />;
  else if (section === "draft" && id)
    page =
      (id === "new" && (!editorTemplateId || template)) || initialDraft ? (
        <Editor
          key={`${route}-${revision}`}
          initial={initialDraft}
          template={template}
          setDirty={setDirty}
          onChange={changed}
          navigate={navigate}
        />
      ) : (
        <Missing kind="draft or starter" />
      );
  else if (section === "drafts" && !id)
    page = (
      <>
        <PageIntro
          eyebrow="Only on this device"
          title="A little room for your ideas."
        >
          <p>
            Private drafts live in this browser. They are not shared with the
            community.
          </p>
        </PageIntro>
        <div className="section-heading">
          <h2>Saved drafts</h2>
          <a className="button primary" href="#/draft/new">
            Start from scratch <Icon name="plus" size={18} />
          </a>
        </div>
        <p role="status">{draftNotice}</p>
        {draftState.error ? (
          <Notice error>
            <p>{draftState.error}</p>
            <div className="actions">
              <button
                className="button"
                onClick={() => setDraftState(loadDrafts())}
              >
                Retry loading
              </button>
              <button className="button danger" onClick={resetDrafts}>
                Reset local drafts
              </button>
            </div>
          </Notice>
        ) : draftState.drafts.length ? (
          <div className="two-grid">
            {draftState.drafts.map((d) => (
              <article className="surface" key={d.id}>
                <Badge>Private · {d.category}</Badge>
                <h2>
                  <a href={`#/draft/${d.id}`} dir="auto">
                    {d.title}
                  </a>
                </h2>
                <p className="small muted">
                  Saved {new Date(d.updatedAt).toLocaleString()} on this device
                  only
                </p>
                <div className="actions">
                  <a className="button" href={`#/draft/${d.id}`}>
                    Edit draft <Icon size={17} />
                  </a>
                  <button
                    className="text-link danger"
                    onClick={() => removeDraft(d.id)}
                  >
                    Delete draft
                  </button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <section className="empty">
            <h3>Your next idea can start here.</h3>
            <p>
              Save a draft from scratch or use one of the four example starters.
            </p>
            <a className="button" href="#/ideas">
              Explore the starters <Icon />
            </a>
          </section>
        )}
      </>
    );
  else page = <Missing />;
  const current =
    section === "" || section === "ideas"
      ? "Ideas"
      : section === "projects"
        ? "Projects"
        : section === "vote"
          ? "Vote"
          : section === "treasury"
            ? "Treasury"
            : "";
  useEffect(() => {
    document.title = `IMDAO · ${current || (section.startsWith("draft") ? "Private drafts" : "Page not found")}`;
  }, [current, section]);
  return (
    <>
      <a
        className="skip-link"
        href="#main"
        onClick={(e) => {
          e.preventDefault();
          document.getElementById("main")?.focus();
        }}
      >
        Skip to content
      </a>
      <header className="site-header">
        <a className="brand" href="#/" aria-label="IMDAO home">
          <Logo />
        </a>
        <nav className="primary-nav" aria-label="Main navigation">
          {["Ideas", "Projects", "Vote", "Treasury"].map((n) => (
            <a
              key={n}
              href={`#/${n.toLowerCase()}`}
              aria-current={current === n ? "page" : undefined}
            >
              {n}
            </a>
          ))}
        </nav>
        <div className="header-actions">
          <a className="button primary new-idea" href="#/draft/new">
            <Icon name="plus" size={17} />
            New idea
          </a>
          <button
            className="theme-toggle"
            aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
            onClick={toggleTheme}
          >
            <Icon name={theme === "dark" ? "sun" : "moon"} />
          </button>
        </div>
      </header>
      <div className="theme-message" role="status">
        {themeError}
      </div>
      <main id="main" tabIndex={-1} className="container">
        {page}
      </main>
      <footer className="site-footer">
        <div>
          <a href="#/" className="footer-name">
            IMDAO
          </a>
          <span>A shared space for what comes next.</span>
        </div>
        <div>
          <a href="#/drafts">Your local drafts</a>
          <span className="small">
            Local preview · live services not connected
          </span>
        </div>
      </footer>
    </>
  );
}
