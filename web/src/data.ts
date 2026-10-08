export const categories = ["Build", "Earn", "Improve", "Experiment"] as const;
export type Category = (typeof categories)[number];
export type Provenance = "demo" | "local";
export type Fields = {
  title: string;
  category: Category;
  problem: string;
  beneficiary: string;
  firstStep: string;
  operator: string;
  budget: string;
  unit: string;
  success: string;
  risks: string;
  references: string;
  customers: string;
  costs: string;
  reporting: string;
};
export type Draft = Fields & {
  id: string;
  provenance: "local";
  sourceTemplateId: string | null;
  updatedAt: string;
};
export type Template = {
  id: string;
  provenance: "demo";
  category: Category;
  title: string;
  description: string;
  beneficiary: string;
  firstStep: string;
  success: string;
  risks: string;
  business: boolean;
};
export const templates: Template[] = [
  {
    id: "wallet-research",
    provenance: "demo",
    category: "Build",
    title: "Make wallet research clearer",
    description:
      "A small tool that helps people understand a wallet’s public activity.",
    beneficiary:
      "Community researchers looking for understandable, source-linked data.",
    firstStep:
      "Sketch a read-only report for one public wallet using sample data.",
    success:
      "Can a reader explain the report and trace each claim to its source?",
    risks: "Misleading labels, privacy concerns and incomplete data.",
    business: false,
  },
  {
    id: "paid-newsletter",
    provenance: "demo",
    category: "Earn",
    title: "Test a niche paid newsletter",
    description:
      "Explore whether a focused research digest is worth paying for.",
    beneficiary: "Readers who need useful research in one narrow subject.",
    firstStep:
      "Choose a niche, interview potential readers and draft one sample issue.",
    success: "What evidence of willingness to pay would justify a small pilot?",
    risks: "Weak demand, publishing costs and overestimating revenue.",
    business: true,
  },
  {
    id: "treasury-reporting",
    provenance: "demo",
    category: "Improve",
    title: "Make the treasury easier to read",
    description:
      "Turn treasury records into a clearer, reusable community report.",
    beneficiary: "Members trying to understand spending and commitments.",
    firstStep:
      "Draft a one-page report separating available funds, reservations and payments.",
    success:
      "Can a reader distinguish principal returns from business proceeds?",
    risks:
      "Stale data, missing context and accidental cross-asset comparisons.",
    business: false,
  },
  {
    id: "builder-project",
    provenance: "demo",
    category: "Experiment",
    title: "Give a small build a clear finish",
    description:
      "Scope a builder project around one useful, reviewable deliverable.",
    beneficiary: "A community with a specific, small problem to solve.",
    firstStep:
      "Describe one deliverable, the intended user and a short review checklist.",
    success:
      "What evidence would show the deliverable works for its intended user?",
    risks: "Scope growth, unclear ownership and untested assumptions.",
    business: false,
  },
];
export type Idea = {
  id: string;
  provenance: "demo";
  category: Category;
  status: "Exploring" | "In discussion" | "Shaping scope";
  title: string;
  summary: string;
  purpose: string;
  benefit: string;
  discussion: string[];
  projectIds: string[];
};
export const ideas: Idea[] = [
  {
    id: "research-notebook",
    provenance: "demo",
    category: "Build",
    status: "Exploring",
    title: "A clearer starting point for wallet research",
    summary:
      "A simple research notebook that turns public wallet activity into something easier to understand.",
    purpose:
      "Explore a read-only notebook that pairs public activity with source links and clear uncertainty labels.",
    benefit:
      "Researchers could check an interpretation without having to reconstruct every step.",
    discussion: [
      "What is the smallest report that would be useful to a first-time researcher?",
      "A useful first test might pair one sample report with a short comprehension interview.",
    ],
    projectIds: ["research-sketch"],
  },
  {
    id: "research-digest",
    provenance: "demo",
    category: "Earn",
    status: "In discussion",
    title: "A little less noise. A useful weekly read.",
    summary:
      "Could a focused newsletter create value for readers? Start with one niche and one good issue.",
    purpose:
      "Discuss a governed offchain-business experiment before requesting any budget or appointing an operator.",
    benefit:
      "Potential readers could help shape a focused digest; the community could learn whether demand exists.",
    discussion: [
      "Who has this problem often enough to consider a paid subscription?",
      "Include delivery costs and a plan for reporting unused funds and proceeds before any funding decision.",
    ],
    projectIds: ["newsletter-pilot"],
  },
  {
    id: "treasury-notes",
    provenance: "demo",
    category: "Improve",
    status: "Shaping scope",
    title: "Treasury updates everyone can follow",
    summary:
      "A shared format for what is available, what is committed and what each payment is for.",
    purpose:
      "Design a plain-language report that explains the treasury’s two buckets and keeps each asset separate.",
    benefit:
      "Members could review spending context without mistaking returned principal for earnings.",
    discussion: [
      "Show reservations inside the relevant bucket, rather than counting them twice.",
      "Link each payment to its decision and retain separate receipt categories.",
    ],
    projectIds: ["report-format"],
  },
];
export type Project = {
  id: string;
  provenance: "demo";
  title: string;
  summary: string;
  state: "Planned" | "In progress" | "Completed";
  owner: string;
  scope: string;
  milestones: { title: string; state: string }[];
  ideaId: string;
  decisionIds: string[];
};
export const projects: Project[] = [
  {
    id: "research-sketch",
    provenance: "demo",
    title: "Wallet research notebook",
    summary: "A small, source-linked sample report.",
    state: "Planned",
    owner: "Not appointed",
    scope:
      "One sample report, a data-source note and a review checklist. No live wallet access or integrations.",
    milestones: [
      { title: "Agree the research question", state: "Planned" },
      { title: "Review a sample report", state: "Planned" },
    ],
    ideaId: "research-notebook",
    decisionIds: [],
  },
  {
    id: "newsletter-pilot",
    provenance: "demo",
    title: "One-issue newsletter pilot",
    summary: "Learn about reader needs before a business experiment.",
    state: "In progress",
    owner: "Not appointed — illustrative workflow only",
    scope:
      "A sample issue and a demand assessment, with costs, risks and receipt reporting. This fixture describes a possible workflow; no work or funding has occurred.",
    milestones: [
      {
        title: "Draft reader interview questions",
        state: "In progress (example)",
      },
      { title: "Review demand and cost assumptions", state: "Planned" },
    ],
    ideaId: "research-digest",
    decisionIds: ["enrollment-example"],
  },
  {
    id: "report-format",
    provenance: "demo",
    title: "A readable treasury report",
    summary: "An example of how a finished project could be documented.",
    state: "Completed",
    owner: "Not appointed — illustrative workflow only",
    scope:
      "A report format separating buckets, reservations, payments and receipts. The completed state is a fixture, not real completed work.",
    milestones: [
      { title: "Define report sections", state: "Completed (example)" },
      { title: "Check clarity with a reader", state: "Completed (example)" },
    ],
    ideaId: "treasury-notes",
    decisionIds: ["payment-example"],
  },
];
export const actionTypes = [
  {
    name: "Manage a recipient",
    method: "Treasury.setRecipient",
    description:
      "Enroll or disable a versioned recipient. Enabling still requires that recipient to accept before receiving payments.",
  },
  {
    name: "Authorize a payment",
    method: "Treasury.pay",
    description:
      "Pay an active recipient from a specified asset and bucket, subject to cash, reservations and lifetime caps. Each milestone needs a fresh decision.",
  },
  {
    name: "Select a pinned fee policy",
    method: "FeeHook.activatePolicy",
    description:
      "Choose the pinned 80/20 or 60/40 development/reserve policy for future fee receipts. Existing balances do not move.",
  },
  {
    name: "Request mock evidence",
    method: "MockOracle.request",
    description:
      "Request a question hash through the local mock oracle. Its answer grants no votes or spending authority.",
  },
] as const;
export type Decision = {
  id: string;
  provenance: "demo";
  title: string;
  state: "Pending" | "Active" | "Queued" | "Executed";
  actionIndex: number;
  purpose: string;
  projectId: string | null;
};
export const decisions: Decision[] = [
  {
    id: "enrollment-example",
    provenance: "demo",
    title: "Review enrollment for a newsletter operator",
    state: "Pending",
    actionIndex: 0,
    purpose:
      "An example of the separate enrollment decision a proposed business operator would need. No operator has been chosen or enrolled.",
    projectId: "newsletter-pilot",
  },
  {
    id: "policy-example",
    provenance: "demo",
    title: "Consider the pinned 60/40 fee policy",
    state: "Active",
    actionIndex: 2,
    purpose:
      "Illustrate a formal decision about allocating future fee receipts to development and reserve. This is not a contract upgrade or an investment mandate.",
    projectId: null,
  },
  {
    id: "payment-example",
    provenance: "demo",
    title: "Record an example reporting milestone payment",
    state: "Executed",
    actionIndex: 1,
    purpose:
      "Illustrate how a payment decision could link to a project. An executed payment does not establish that the project was delivered.",
    projectId: "report-format",
  },
];
export const treasury = {
  id: "treasury-demo",
  provenance: "demo" as const,
  asset: "MockAsset",
  buckets: [
    {
      id: "development",
      name: "Development",
      balance: 8000,
      reserved: 1200,
      paid: 1000,
    },
    { id: "reserve", name: "Reserve", balance: 2000, reserved: 300, paid: 0 },
  ],
  receipts: { fees: 10700, principal: 200, proceeds: 100 },
  payments: [
    {
      id: "demo-payment-1",
      projectId: "report-format",
      decisionId: "payment-example",
      title: "Reporting milestone",
      asset: "MockAsset",
      amount: 1000,
      returned: 200,
      proceeds: 100,
      state: "Paid (example)",
    },
  ],
};
export function blankFields(): Fields {
  return {
    title: "",
    category: "Build",
    problem: "",
    beneficiary: "",
    firstStep: "",
    operator: "",
    budget: "",
    unit: "",
    success: "",
    risks: "",
    references: "",
    customers: "",
    costs: "",
    reporting: "",
  };
}
export function fromTemplate(t: Template): Fields {
  return {
    ...blankFields(),
    title: t.title,
    category: t.category,
    problem: t.description,
    beneficiary: t.beneficiary,
    firstStep: t.firstStep,
    risks: t.risks,
  };
}
export const fieldLabels: Record<keyof Fields, string> = {
  title: "Title",
  category: "Category",
  problem: "Problem or opportunity",
  beneficiary: "Who benefits?",
  firstStep: "First step",
  operator: "Proposed operator",
  budget: "Budget amount",
  unit: "Asset or unit",
  success: "Success criterion",
  risks: "Risks",
  references: "References (optional)",
  customers: "Potential customers",
  costs: "Cost assumptions",
  reporting: "Unused funds and proceeds reporting",
};
