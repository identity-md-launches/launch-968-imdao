import type { ReactNode } from "react";
export function Icon({
  name = "arrow",
  size = 20,
}: {
  name?: string;
  size?: number;
}) {
  const paths: Record<string, ReactNode> = {
    arrow: (
      <>
        <path d="M5 12h14M13 6l6 6-6 6" />
      </>
    ),
    northeast: (
      <>
        <path d="M6 18 18 6M6 6h12v12" />
      </>
    ),
    down: (
      <>
        <path d="M12 5v14m-6-6 6 6 6-6" />
      </>
    ),
    plus: (
      <>
        <path d="M12 5v14M5 12h14" />
      </>
    ),
    sun: (
      <>
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5" />
      </>
    ),
    moon: <path d="M20 14a8 8 0 0 1-10-10 8.5 8.5 0 1 0 10 10Z" />,
    Build: (
      <>
        <rect x="4" y="5" width="16" height="14" rx="3" />
        <path d="m10 9-3 3 3 3m4-6 3 3-3 3" />
      </>
    ),
    Earn: (
      <>
        <rect x="3" y="5" width="18" height="14" rx="3" />
        <path d="m4 7 8 6 8-6" />
      </>
    ),
    Improve: (
      <>
        <path d="M8 4h8l3 3v13H5V4h3m0 5h8m-8 4h8m-8 4h5" />
      </>
    ),
    Experiment: (
      <>
        <path d="M9 3h6m-5 0v6l-6 10a1 1 0 0 0 1 2h14a1 1 0 0 0 1-2L14 9V3M7 15h10" />
      </>
    ),
    search: (
      <>
        <circle cx="10.5" cy="10.5" r="6.5" />
        <path d="m16 16 5 5" />
      </>
    ),
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name] ?? paths.arrow}
    </svg>
  );
}
export function Logo() {
  return (
    <svg className="logo" viewBox="0 0 379.5 120" role="img" aria-label="IMDAO">
      <g transform="translate(24 33) scale(3)" fill="currentColor">
        {[0, 7, 14].flatMap((y) =>
          [0, 7, 14].map((x) => (
            <rect
              key={`${x}-${y}`}
              x={x}
              y={y}
              width="4"
              height="4"
              opacity={(x === 0 && y === 7) || (x === 7 && y === 14) ? 0.25 : 1}
            />
          )),
        )}
      </g>
      <text
        x="106"
        y="90"
        fontFamily="IBM Plex Mono"
        fontWeight="500"
        fontSize="84.507"
        letterSpacing="-2"
        fill="currentColor"
      >
        IMDAO
      </text>
    </svg>
  );
}
export function Badge({ children }: { children: ReactNode }) {
  return <span className="badge">{children}</span>;
}
export function Notice({
  children,
  error = false,
}: {
  children: ReactNode;
  error?: boolean;
}) {
  return (
    <div
      className={`notice${error ? " error" : ""}`}
      role={error ? "alert" : undefined}
    >
      {children}
    </div>
  );
}
export function PageIntro({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <header className="page-intro">
      <p className="eyebrow">{eyebrow}</p>
      <h1 tabIndex={-1}>{title}</h1>
      <div className="intro-copy">{children}</div>
    </header>
  );
}
export function Missing({ kind = "page" }: { kind?: string }) {
  return (
    <section className="empty">
      <h1 tabIndex={-1}>This {kind} isn’t here</h1>
      <p>
        The link may be incomplete, or a local draft may have been deleted on
        this device.
      </p>
      <a className="button" href="#/">
        Back to ideas <Icon />
      </a>
      <a className="text-link" href="#/drafts">
        Open local drafts
      </a>
    </section>
  );
}
export function DetailSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="detail-section">
      <h2>{title}</h2>
      {children}
    </section>
  );
}
export function Journey() {
  return (
    <ol className="journey" aria-label="Community journey">
      {["Idea", "Discussion", "Vote", "Build", "Result"].map((s, i) => (
        <li key={s}>
          <span>{s}</span>
          {i < 4 && (
            <span className="journey-arrow" aria-hidden="true">
              →
            </span>
          )}
        </li>
      ))}
    </ol>
  );
}
