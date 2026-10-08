import { useState } from "react";
import {
  categories,
  templates,
  ideas,
  projects,
  decisions,
  actionTypes,
  treasury,
} from "./data";
import {
  Badge,
  DetailSection,
  Icon,
  Journey,
  Missing,
  Notice,
  PageIntro,
} from "./components";
export function Starters() {
  return (
    <section className="starters" aria-labelledby="starters-heading">
      <div className="section-heading">
        <div>
          <p className="eyebrow">A little inspiration</p>
          <h2 id="starters-heading">Need a starting point?</h2>
          <p>Examples, not approved proposals. Make one your own.</p>
        </div>
        <a className="text-link" href="#/draft/new">
          Start from scratch <Icon name="plus" size={17} />
        </a>
      </div>
      <div className="starter-grid">
        {templates.map((t) => (
          <article className="starter-card" key={t.id}>
            <div className="card-top">
              <span className="category">
                <Icon name={t.category} />
                {t.category}
              </span>
              <span className="mono small">Example</span>
            </div>
            <h3>{t.title}</h3>
            <p>{t.description}</p>
            <details>
              <summary>Explore this starter</summary>
              <dl>
                <dt>Who benefits</dt>
                <dd>{t.beneficiary}</dd>
                <dt>First experiment</dt>
                <dd>{t.firstStep}</dd>
                <dt>Success-check prompt</dt>
                <dd>{t.success}</dd>
                <dt>Main risks</dt>
                <dd>{t.risks}</dd>
              </dl>
            </details>
            <a className="starter-action" href={`#/draft/new?template=${t.id}`}>
              Use as a starting point <Icon name="northeast" size={17} />
            </a>
          </article>
        ))}
      </div>
    </section>
  );
}
export function IdeasPage({ home }: { home: boolean }) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("All");
  const [status, setStatus] = useState("All");
  const filtered = ideas.filter(
    (i) =>
      (category === "All" || i.category === category) &&
      (status === "All" || i.status === status) &&
      `${i.title} ${i.summary} ${i.category}`
        .toLowerCase()
        .includes(query.trim().toLowerCase()),
  );
  function explore() {
    document
      .getElementById("community-heading")
      ?.scrollIntoView({ block: "start" });
    document
      .getElementById("community-heading")
      ?.focus({ preventScroll: true });
  }
  return (
    <>
      {home ? (
        <section className="hero">
          <p className="eyebrow hero-kicker">
            <span className="small-dot" />
            Ideas grow here
          </p>
          <h1 tabIndex={-1}>
            A place for the
            <br className="hero-break" /> next good idea.
          </h1>
          <p className="hero-subtitle">
            Bring an idea. Make it better together.
            <br className="mobile-break" /> Decide what happens next.
          </p>
          <button className="button accent" onClick={explore}>
            Explore the ideas <Icon name="down" size={18} />
          </button>
          <Journey />
        </section>
      ) : (
        <PageIntro
          eyebrow="Ideas & discussion"
          title="Good ideas start with a conversation."
        >
          <p>
            Explore a possibility, ask a better question, or shape an idea of
            your own.
          </p>
        </PageIntro>
      )}
      <section className="community" aria-labelledby="community-heading">
        <div className="section-heading">
          <div>
            <h2 id="community-heading" tabIndex={-1}>
              Around the community
            </h2>
            <p>A few possibilities to think about, together.</p>
          </div>
          <span className="demo-note">
            <span className="small-dot" />
            Illustrative ideas · not live activity
          </span>
        </div>
        <div className="filters">
          <label className="search-label">
            <span className="sr-only">Search ideas</span>
            <Icon name="search" size={19} />
            <input
              type="search"
              placeholder="Find an idea…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </label>
          <div className="filter-select">
            <label htmlFor="category-filter">Category</label>
            <select
              id="category-filter"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            >
              <option value="All">All categories</option>
              {categories.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </div>
          <div className="filter-select">
            <label htmlFor="status-filter">Status</label>
            <select
              id="status-filter"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
            >
              <option value="All">All stages</option>
              {["Exploring", "In discussion", "Shaping scope"].map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </div>
        </div>
        <p className="result-status" role="status">
          {query || category !== "All" || status !== "All"
            ? `${filtered.length} illustrative ${filtered.length === 1 ? "idea" : "ideas"} shown`
            : "Browse the example ideas"}
        </p>
        {filtered.length ? (
          <div className="idea-grid">
            {filtered.map((i) => (
              <article
                className={`idea-card tone-${ideas.indexOf(i)}`}
                key={i.id}
              >
                <a
                  href={`#/ideas/${i.id}`}
                  aria-label={`Read idea: ${i.title}`}
                >
                  <div className="card-top">
                    <span className="category">
                      <Icon name={i.category} />
                      {i.category}
                    </span>
                    <Badge>{i.status}</Badge>
                  </div>
                  <h3>{i.title}</h3>
                  <p>{i.summary}</p>
                  <div className="card-bottom">
                    <span className="mono small">Demo idea</span>
                    <span className="card-link">
                      Read idea <Icon name="northeast" size={18} />
                    </span>
                  </div>
                </a>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty">
            <h3>No ideas match {query ? `“${query}”` : "these filters"}</h3>
            <p>Try another phrase or explore all of the example ideas.</p>
            <button
              className="button"
              onClick={() => {
                setQuery("");
                setCategory("All");
                setStatus("All");
              }}
            >
              Clear filters
            </button>
          </div>
        )}
      </section>
      <Starters />
      <section className="closing-note">
        <span className="small-dot" />
        <p>
          It doesn’t need to be fully formed.
          <br />
          <strong>A useful question is a good beginning.</strong>
        </p>
      </section>
    </>
  );
}
export function IdeaDetail({ id }: { id: string }) {
  const i = ideas.find((x) => x.id === id);
  if (!i) return <Missing kind="idea" />;
  return (
    <>
      <a className="back-link" href="#/ideas">
        ← All ideas
      </a>
      <PageIntro eyebrow={`${i.category} · Illustrative idea`} title={i.title}>
        <Badge>{i.status}</Badge>
        <p>{i.summary}</p>
      </PageIntro>
      <div className="detail-layout">
        <div>
          <DetailSection title="The purpose">
            <p>{i.purpose}</p>
          </DetailSection>
          <DetailSection title="Who could benefit">
            <p>{i.benefit}</p>
          </DetailSection>
          <DetailSection title="A conversation to explore">
            <p className="muted">
              Read-only illustrative discussion. These prompts are examples, not
              posts by community members.
            </p>
            {i.discussion.map((d, n) => (
              <blockquote key={d}>
                <span className="mono small">Discussion prompt {n + 1}</span>
                <p>{d}</p>
              </blockquote>
            ))}
          </DetailSection>
        </div>
        <aside className="surface">
          <h2>From idea to possibility</h2>
          <p>
            An idea starts a discussion. A formal proposal is a separate
            governance decision.
          </p>
          <h3>Related project</h3>
          {i.projectIds.map((id) => (
            <a className="text-link" key={id} href={`#/projects/${id}`}>
              {projects.find((p) => p.id === id)?.title} <Icon size={17} />
            </a>
          ))}
          <a
            className="button"
            href={`#/draft/new?template=${templates.find((t) => t.category === i.category)?.id}`}
          >
            Make a draft of your own <Icon name="plus" size={17} />
          </a>
        </aside>
      </div>
    </>
  );
}
export function ProjectsPage() {
  const [filter, setFilter] = useState("All");
  return (
    <>
      <PageIntro eyebrow="Projects" title="Give an idea a next step.">
        <p>
          Follow scope, milestones and the decisions behind a piece of work.
        </p>
      </PageIntro>
      <Notice>
        Demo projects only. The states below illustrate a workflow; they do not
        report real progress, appointed operators or completed work.
      </Notice>
      <div className="segmented" aria-label="Filter projects">
        {["All", "Planned", "In progress", "Completed"].map((s) => (
          <button
            key={s}
            aria-pressed={filter === s}
            onClick={() => setFilter(s)}
          >
            {s}
          </button>
        ))}
      </div>
      <div className="idea-grid">
        {projects
          .filter((p) => filter === "All" || p.state === filter)
          .map((p) => (
            <article className="surface project-card" key={p.id}>
              <Badge>{p.state} · demo</Badge>
              <h2>
                <a href={`#/projects/${p.id}`}>{p.title}</a>
              </h2>
              <p>{p.summary}</p>
              <p className="small muted">Owner: {p.owner}</p>
              <a className="text-link" href={`#/projects/${p.id}`}>
                View project <Icon name="northeast" size={17} />
              </a>
            </article>
          ))}
      </div>
    </>
  );
}
export function ProjectDetail({ id }: { id: string }) {
  const p = projects.find((x) => x.id === id);
  if (!p) return <Missing kind="project" />;
  return (
    <>
      <a className="back-link" href="#/projects">
        ← All projects
      </a>
      <PageIntro eyebrow="Illustrative project" title={p.title}>
        <Badge>{p.state} · demo</Badge>
        <p>{p.summary}</p>
      </PageIntro>
      <Notice>
        This is a fixture, including its milestone states. No real execution or
        completion is claimed.
      </Notice>
      <div className="detail-layout">
        <div>
          <DetailSection title="Scope">
            <p>{p.scope}</p>
          </DetailSection>
          <DetailSection title="Milestones">
            <ol className="milestones">
              {p.milestones.map((m) => (
                <li key={m.title}>
                  <span>{m.title}</span>
                  <Badge>{m.state}</Badge>
                </li>
              ))}
            </ol>
          </DetailSection>
          <DetailSection title="Result & evidence">
            <p>
              No real deliverable or completion evidence is connected. A vote or
              an executed payment alone does not demonstrate a result.
            </p>
          </DetailSection>
        </div>
        <aside className="surface">
          <h2>Project context</h2>
          <h3>Owner status</h3>
          <p>{p.owner}</p>
          <h3>Started with an idea</h3>
          <a className="text-link" href={`#/ideas/${p.ideaId}`}>
            {ideas.find((i) => i.id === p.ideaId)?.title}
          </a>
          <h3>Linked decisions</h3>
          {p.decisionIds.length ? (
            p.decisionIds.map((id) => (
              <a className="text-link" href={`#/vote/${id}`} key={id}>
                {decisions.find((d) => d.id === id)?.title}
              </a>
            ))
          ) : (
            <p>No formal decision linked.</p>
          )}
        </aside>
      </div>
    </>
  );
}
function GovernanceRules() {
  return (
    <DetailSection title="How a formal decision works">
      <p>
        Informal ideas are not governance proposals. The local contract
        prototype accepts one allowed action per proposal.
      </p>
      <ol className="rules">
        <li>
          <strong>Pending → Active.</strong> Proposing requires 10,000 base
          IMDAO delegated votes at the previous block. The snapshot is the
          proposal block + 1; voting runs for the following 100 blocks.
        </li>
        <li>
          <strong>Defeated or Succeeded.</strong> Base FOR + ABSTAIN must reach
          40,000 IMDAO, and weighted FOR must exceed weighted AGAINST. Weight is
          base IMDAO + the smaller of delegated MockIMD or 25% of base IMDAO.
        </li>
        <li>
          <strong>Queued → Executed.</strong> A successful proposal can be
          queued, then executed after a fixed 3,600-second delay. Payments
          reserve cash and cap capacity at queue time and have a seven-day
          execution window after becoming ready.
        </li>
        <li>
          <strong>Cancelled.</strong> The proposer may cancel a known,
          unexecuted proposal. Anyone may cancel a queued payment if it has
          expired or its recipient status/version is invalid.
        </li>
      </ol>
      <p className="muted">
        Execution records the contract action. It does not prove delivery,
        business success or completion. These rules describe the repository
        prototype, not a connected deployment.
      </p>
    </DetailSection>
  );
}
export function VotePage() {
  return (
    <>
      <PageIntro eyebrow="Vote" title="Thoughtful decisions, shared direction.">
        <p>Understand what a formal decision can do and what comes after it.</p>
      </PageIntro>
      <Notice>
        <strong>Live governance is not connected.</strong> All decisions below
        are read-only examples. No votes, transactions or submissions can be
        made here.
      </Notice>
      <div className="decision-list">
        {decisions.map((d) => (
          <a className="decision-row" href={`#/vote/${d.id}`} key={d.id}>
            <span>
              <span className="mono small">
                {actionTypes[d.actionIndex].name} · example
              </span>
              <h2>{d.title}</h2>
            </span>
            <span className="row-end">
              <Badge>{d.state} · demo</Badge>
              <Icon name="northeast" />
            </span>
          </a>
        ))}
      </div>
      <GovernanceRules />
      <DetailSection title="Four allowed action types">
        <div className="two-grid">
          {actionTypes.map((a) => (
            <article className="surface" key={a.name}>
              <h3>{a.name}</h3>
              <p>{a.description}</p>
              <code>{a.method}</code>
            </article>
          ))}
        </div>
        <p className="muted">
          No generic execution, arbitrary upgrades, asset conversion or
          investment mandate is supported by this prototype.
        </p>
      </DetailSection>
    </>
  );
}
export function VoteDetail({ id }: { id: string }) {
  const d = decisions.find((x) => x.id === id);
  if (!d) return <Missing kind="decision" />;
  return (
    <>
      <a className="back-link" href="#/vote">
        ← All example decisions
      </a>
      <PageIntro
        eyebrow="Formal governance · read-only example"
        title={d.title}
      >
        <Badge>{d.state} · demo</Badge>
        <p>{d.purpose}</p>
      </PageIntro>
      <Notice>
        Live governance is not connected. This example is not an onchain
        proposal. Vote totals, voters, block numbers and transaction records are
        not connected.
      </Notice>
      <div className="detail-layout">
        <div>
          <DetailSection title="The allowed action">
            <h3>{actionTypes[d.actionIndex].name}</h3>
            <p>{actionTypes[d.actionIndex].description}</p>
            <code>{actionTypes[d.actionIndex].method}</code>
          </DetailSection>
          <GovernanceRules />
        </div>
        <aside className="surface">
          <h2>Decision context</h2>
          <dl>
            <dt>Example state</dt>
            <dd>{d.state}</dd>
            <dt>Live tallies</dt>
            <dd>Not connected</dd>
            <dt>Execution evidence</dt>
            <dd>Not connected</dd>
          </dl>
          {d.projectId && (
            <a className="text-link" href={`#/projects/${d.projectId}`}>
              View related project <Icon size={17} />
            </a>
          )}
          <p className="small muted">
            No executable action data is created by this website.
          </p>
        </aside>
      </div>
    </>
  );
}
const amount = (n: number) => `${n.toLocaleString("en-US")} MockAsset`;
export function TreasuryPage() {
  return (
    <>
      <PageIntro
        eyebrow="Treasury"
        title="A clearer picture of shared resources."
      >
        <p>Keep the purpose of each bucket, commitment and receipt in view.</p>
      </PageIntro>
      <div className="connection-row">
        <span>Live treasury balances</span>
        <Badge>Not connected</Badge>
      </div>
      <Notice>
        Illustrative ledger only · all amounts below use valueless{" "}
        <strong>MockAsset</strong> units. No real balances, income or funding
        are shown.
      </Notice>
      <div className="two-grid treasury-buckets">
        {treasury.buckets.map((b) => (
          <article className="surface" key={b.name}>
            <p className="eyebrow">Demo bucket</p>
            <h2>{b.name}</h2>
            <p className="bucket-description">
              {b.name === "Development"
                ? "For work with a defined purpose and a reviewed next step."
                : "For resources held in reserve, subject to separate decisions."}
            </p>
            <dl className="money-list">
              <div>
                <dt>Available</dt>
                <dd>{amount(b.balance - b.reserved)}</dd>
              </div>
              <div>
                <dt>Reserved (inside balance)</dt>
                <dd>{amount(b.reserved)}</dd>
              </div>
              <div>
                <dt>Current bucket balance</dt>
                <dd>{amount(b.balance)}</dd>
              </div>
              <div>
                <dt>Gross paid to date</dt>
                <dd>{amount(b.paid)}</dd>
              </div>
            </dl>
          </article>
        ))}
      </div>
      <DetailSection title="Payments & linked decisions">
        <div className="table-wrap">
          <table>
            <caption>Demo payment history · MockAsset only</caption>
            <thead>
              <tr>
                <th scope="col">Purpose</th>
                <th scope="col">Gross payment</th>
                <th scope="col">Principal returned</th>
                <th scope="col">Business proceeds</th>
              </tr>
            </thead>
            <tbody>
              {treasury.payments.map((p) => (
                <tr key={p.id}>
                  <td>
                    <a href={`#/vote/${p.decisionId}`}>{p.title}</a>
                    <span className="table-note">{p.state}</span>
                  </td>
                  <td>{amount(p.amount)}</td>
                  <td>{amount(p.returned)}</td>
                  <td>{amount(p.proceeds)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </DetailSection>
      <div className="two-grid">
        <DetailSection title="Returned principal">
          <p className="receipt-amount">
            {amount(treasury.receipts.principal)}{" "}
            <span className="mono small">demo</span>
          </p>
          <p>
            Unused funds returned by the original payment recipient. These are
            not earnings. Cumulative returns cannot exceed the original payment.
          </p>
        </DetailSection>
        <DetailSection title="Business proceeds">
          <p className="receipt-amount">
            {amount(treasury.receipts.proceeds)}{" "}
            <span className="mono small">demo</span>
          </p>
          <p>
            Separately declared proceeds associated with a payment. They are not
            audited profit or proof of business performance.
          </p>
        </DetailSection>
      </div>
      <details className="surface ledger-notes">
        <summary>How this illustrative ledger adds up</summary>
        <p>
          10,700 MockAsset fee receipts + 200 MockAsset principal returns + 100
          MockAsset proceeds − 1,000 MockAsset gross payments = 10,000 MockAsset
          across the current buckets. The 1,500 MockAsset reserved is already
          included in those buckets.
        </p>
        <p>
          Receipts return to the original payment’s asset and bucket. They do
          not reduce lifetime gross payment cap usage. No cross-asset portfolio
          value is calculated. Real IMDAO and MockAsset balances remain not
          connected.
        </p>
      </details>
    </>
  );
}
