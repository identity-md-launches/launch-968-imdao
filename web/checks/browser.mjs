// Run from the repository root. Dependencies for this check live outside the app.
import { createServer } from "node:http";
import { readFile, stat, mkdir, writeFile } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import assert from "node:assert/strict";
const { chromium } = await import(
  process.env.IMDAO_PLAYWRIGHT_MODULE || "playwright"
);
const dist = resolve("dist");
const artifact = resolve("artifacts");
await mkdir(artifact, { recursive: true });
const server = createServer(async (req, res) => {
  try {
    if (req.url === "/favicon.ico") {
      res.writeHead(204);
      res.end();
      return;
    }
    const name = decodeURIComponent(
      new URL(req.url, "http://localhost").pathname,
    ).replace(/^\/preview\//, "");
    const file = resolve(dist, name || "index.html");
    if (!file.startsWith(dist + sep)) throw Error("path");
    const info = await stat(file);
    if (!info.isFile()) throw Error("file");
    const types = {
      ".html": "text/html",
      ".js": "text/javascript",
      ".css": "text/css",
      ".woff2": "font/woff2",
      ".txt": "text/plain",
    };
    res.writeHead(200, {
      "Content-Type": types[extname(file)] || "application/octet-stream",
    });
    res.end(await readFile(file));
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}/preview/`;
const browser = await chromium.launch({
  executablePath: process.env.IMDAO_CHROMIUM || undefined,
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});
const results = [];
const consoleErrors = [];
const resources = [];
const contrast = [];
const audits = [];
let page;
async function makePage(options = {}, capture = true) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1050 },
    colorScheme: "light",
    ...options,
  });
  const p = await context.newPage();
  p.setDefaultTimeout(6000);
  if (capture) p.on("pageerror", (e) => consoleErrors.push(e.message));
  if (capture)
    p.on("console", (m) => {
      if (m.type() === "error") consoleErrors.push(m.text());
    });
  if (capture) p.on("requestfailed", (r) => resources.push(r.url()));
  if (capture)
    p.on("response", (r) => {
      if (r.status() >= 400) resources.push(`${r.status()} ${r.url()}`);
    });
  return p;
}
async function check(name, run) {
  try {
    await run();
    results.push({ name, result: "PASS" });
    console.log("PASS", name);
  } catch (e) {
    results.push({ name, result: "FAIL", error: String(e.message) });
    console.error("FAIL", name, e.message);
  }
}
async function settle() {
  await page.evaluate(
    () =>
      new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
}
async function goto(route = "/") {
  await page.goto(base + "#" + route);
  await settle();
  await page.locator("h1").waitFor();
}
async function theme() {
  return page.locator("html").getAttribute("data-theme");
}
async function noOverflow() {
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
  );
}
async function axe(label) {
  if (!process.env.IMDAO_AXE_SCRIPT) return;
  await page.addScriptTag({ path: process.env.IMDAO_AXE_SCRIPT });
  const result = await page.evaluate(async () => {
    const r = await window.axe.run(document, {
      runOnly: {
        type: "tag",
        values: ["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"],
      },
    });
    return {
      violations: r.violations.map((x) => ({
        id: x.id,
        impact: x.impact,
        nodes: x.nodes.map((n) => n.target),
      })),
      incomplete: r.incomplete.map((x) => ({
        id: x.id,
        nodes: x.nodes.map((n) => ({
          target: n.target,
          summary: n.failureSummary,
        })),
      })),
    };
  });
  audits.push({ label, ...result });
  assert.equal(result.violations.length, 0, JSON.stringify(result.violations));
}
async function measure(label) {
  contrast.push({
    label,
    ...(await page.evaluate(() => {
      function rgb(s) {
        return (s.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
      }
      function lum(s) {
        return rgb(s)
          .map((c) => {
            c /= 255;
            return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
          })
          .reduce((a, x, i) => a + x * [0.2126, 0.7152, 0.0722][i], 0);
      }
      function bg(e) {
        for (let p = e; p; p = p.parentElement) {
          const b = getComputedStyle(p).backgroundColor;
          if (b !== "rgba(0, 0, 0, 0)" && b !== "transparent") return b;
        }
        return getComputedStyle(document.body).backgroundColor;
      }
      const pairs = [
        ".hero-subtitle",
        ".demo-note",
        ".idea-card p",
        ".badge",
        ".primary-nav a",
        ".button.primary",
        ".button.accent",
        ".starter-card>p",
      ];
      return {
        pairs: pairs
          .map((selector) => {
            const el = document.querySelector(selector);
            if (!el) return null;
            const fg = getComputedStyle(el).color,
              b = bg(el);
            const a = lum(fg),
              c = lum(b);
            return {
              selector,
              foreground: fg,
              background: b,
              ratio: +(
                (Math.max(a, c) + 0.05) /
                (Math.min(a, c) + 0.05)
              ).toFixed(2),
            };
          })
          .filter(Boolean),
      };
    })),
  });
  const last = contrast.at(-1);
  assert(
    last.pairs.every((p) => p.ratio >= 4.5),
    JSON.stringify(last),
  );
}
try {
  page = await makePage();
  await check(
    "Home renders locally at a static subpath with the exact hero",
    async () => {
      await goto();
      assert.equal(
        await page.locator("h1").innerText(),
        "A place for the\nnext good idea.",
      );
      assert.equal(await page.locator(".idea-card").count(), 3);
    },
  );
  await check(
    "Full IBM Plex Mono font loads; exact nine-square logo geometry",
    async () => {
      await page.evaluate(() => document.fonts.ready);
      assert(
        await page.evaluate(() =>
          document.fonts.check('500 16px "IBM Plex Mono"'),
        ),
      );
      assert.equal(await page.locator(".logo rect").count(), 9);
      assert.equal(await page.locator('.logo rect[opacity="0.25"]').count(), 2);
    },
  );
  await check(
    "Light system preference, system changes, remembered manual override",
    async () => {
      assert.equal(await theme(), "light");
      await page.emulateMedia({ colorScheme: "dark" });
      await page.waitForFunction(
        () => document.documentElement.dataset.theme === "dark",
      );
      await page.getByRole("button", { name: "Switch to light theme" }).click();
      await settle();
      assert.equal(await theme(), "light");
      await page.reload();
      assert.equal(await theme(), "light");
      await page.emulateMedia({ colorScheme: "dark" });
      assert.equal(await theme(), "light");
    },
  );
  await check(
    "First-paint bootstrap uses dark system or stored preference before React",
    async () => {
      const p = await makePage({ colorScheme: "dark" }, false);
      await p.route("**/assets/*.js", (r) => r.abort());
      await p.goto(base);
      assert.equal(await p.locator("html").getAttribute("data-theme"), "dark");
      await p.evaluate(() => localStorage.setItem("imdao.theme.v1", "light"));
      await p.reload();
      assert.equal(await p.locator("html").getAttribute("data-theme"), "light");
      await p.context().close();
    },
  );
  await check(
    "Explore button reaches the feed; query and category/status filters work",
    async () => {
      await page.getByRole("button", { name: "Explore the ideas" }).click();
      await settle();
      assert.equal(
        await page.evaluate(() => document.activeElement.id),
        "community-heading",
      );
      await page
        .getByRole("searchbox", { name: "Search ideas" })
        .fill("wallet");
      assert.equal(await page.locator(".idea-card").count(), 1);
      await page.getByLabel("Category", { exact: true }).selectOption("Earn");
      assert(await page.getByText("No ideas match").isVisible());
      await page.getByRole("button", { name: "Clear filters" }).click();
      await settle();
      await page
        .getByLabel("Status", { exact: true })
        .selectOption("In discussion");
      assert.equal(await page.locator(".idea-card").count(), 1);
      await page.getByLabel("Status", { exact: true }).selectOption("All");
    },
  );
  await check(
    "Idea detail, read-only discussion and project backlink work",
    async () => {
      await page.locator(".idea-card a").first().click();
      await settle();
      assert(
        await page
          .getByRole("heading", { name: "A conversation to explore" })
          .isVisible(),
      );
      await page
        .getByRole("link", { name: "Wallet research notebook", exact: true })
        .click();
      await settle();
      assert(
        await page.getByRole("heading", { name: "Milestones" }).isVisible(),
      );
      await page
        .getByRole("link", {
          name: "A clearer starting point for wallet research",
          exact: true,
        })
        .click();
      await settle();
      assert(page.url().endsWith("/ideas/research-notebook"));
    },
  );
  await check("All project states and all detail routes render", async () => {
    await goto("/projects");
    for (const name of ["Planned", "In progress", "Completed"]) {
      await page.getByRole("button", { name, exact: true }).click();
      await settle();
      assert.equal(await page.locator(".project-card").count(), 1);
    }
    for (const id of ["research-sketch", "newsletter-pilot", "report-format"]) {
      await goto("/projects/" + id);
      assert(
        await page
          .getByRole("heading", { name: "Result & evidence" })
          .isVisible(),
      );
    }
  });
  await check(
    "Governance overview and every example action detail render",
    async () => {
      await goto("/vote");
      assert.equal(await page.locator(".decision-row").count(), 3);
      for (const id of [
        "enrollment-example",
        "policy-example",
        "payment-example",
      ]) {
        await goto("/vote/" + id);
        assert(
          await page
            .getByRole("heading", { name: "The allowed action" })
            .isVisible(),
        );
        assert(
          (await page.getByText("Not connected", { exact: true }).count()) >= 2,
        );
      }
    },
  );
  await check(
    "Treasury separates available, reserved, paid, principal and proceeds",
    async () => {
      await goto("/treasury");
      assert(
        await page.getByText("6,800 MockAsset", { exact: true }).isVisible(),
      );
      assert(
        await page.getByText("1,700 MockAsset", { exact: true }).isVisible(),
      );
      assert(
        await page
          .getByRole("heading", { name: "Returned principal" })
          .isVisible(),
      );
      assert(
        await page
          .getByRole("heading", { name: "Business proceeds" })
          .isVisible(),
      );
      await page.getByText("How this illustrative ledger adds up").click();
      await settle();
      assert(
        await page
          .getByText("10,700 MockAsset fee receipts", { exact: false })
          .isVisible(),
      );
    },
  );
  await check(
    "All four starters retain provenance, prefill fields, and stay editable",
    async () => {
      for (const id of [
        "wallet-research",
        "paid-newsletter",
        "treasury-reporting",
        "builder-project",
      ]) {
        await goto("/ideas");
        const link = page.locator(`a[href="#/draft/new?template=${id}"]`);
        await link.click();
        await settle();
        assert.notEqual(
          await page.getByLabel("Title", { exact: false }).inputValue(),
          "",
        );
        assert.equal(
          await page.getByLabel("Proposed operator").inputValue(),
          "",
        );
        assert.equal(await page.getByLabel("Budget amount").inputValue(), "");
        if (id === "paid-newsletter")
          assert(await page.getByLabel("Potential customers").isVisible());
        await page
          .getByRole("button", { name: "Save draft", exact: true })
          .click();
        await settle();
        assert(
          await page
            .getByText(
              "Saved on this device only. This private draft has not been submitted.",
            )
            .isVisible(),
        );
        const drafts = await page.evaluate(
          () => JSON.parse(localStorage.getItem("imdao.drafts.v1")).drafts,
        );
        assert.equal(drafts[0].sourceTemplateId, id);
        assert.equal(drafts[0].provenance, "local");
      }
    },
  );
  await check(
    "Required fields validate inline and focus the first invalid input",
    async () => {
      await goto("/draft/new");
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .click();
      await settle();
      assert.equal(await page.locator('[aria-invalid="true"]').count(), 3);
      assert.equal(
        await page.evaluate(() => document.activeElement.id),
        "field-title",
      );
    },
  );
  await check(
    "Scratch draft previews missing fields and treats user input as text",
    async () => {
      await page
        .getByLabel("Title", { exact: false })
        .fill("<img src=x onerror=alert(1)>");
      await page
        .getByLabel("Problem or opportunity")
        .fill("Understand a specific community problem.");
      await page
        .getByLabel("First step")
        .fill("Interview one prospective user.");
      await page.getByRole("button", { name: "Preview draft" }).click();
      await settle();
      assert(
        await page
          .getByRole("heading", { name: "<img src=x onerror=alert(1)>" })
          .isVisible(),
      );
      assert.equal(await page.locator(".draft-preview img").count(), 0);
      assert(
        (await page.getByText("Not specified", { exact: true }).count()) > 0,
      );
      await page
        .getByRole("button", { name: "Edit draft", exact: true })
        .click();
      await settle();
    },
  );
  await check(
    "Budget requires a valid number and a matching asset or unit",
    async () => {
      await page.getByLabel("Budget amount").fill("twelve");
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .click();
      await settle();
      assert(
        await page
          .getByText("Enter a nonnegative number", { exact: false })
          .isVisible(),
      );
      await page.getByLabel("Budget amount").fill("12");
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .click();
      await settle();
      assert(
        await page
          .getByText("Name the asset or unit", { exact: false })
          .isVisible(),
      );
      await page.getByLabel("Asset or unit").fill("hours");
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .click();
      await settle();
      assert(
        await page
          .getByText(
            "Saved on this device only. This private draft has not been submitted.",
          )
          .isVisible(),
      );
    },
  );
  let scratchId;
  await check(
    "Saved drafts reopen after reload; edits persist to the same ID",
    async () => {
      scratchId = await page.evaluate(
        () =>
          JSON.parse(localStorage.getItem("imdao.drafts.v1")).drafts.find(
            (d) => d.sourceTemplateId === null,
          ).id,
      );
      await goto("/drafts");
      await page.reload();
      await page.locator(`a[href="#/draft/${scratchId}"]`).first().click();
      await settle();
      assert.equal(
        await page.getByLabel("Asset or unit").inputValue(),
        "hours",
      );
      await page
        .getByLabel("Title", { exact: false })
        .fill("A small, useful experiment");
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .click();
      await settle();
      await page.reload();
      assert.equal(
        await page.getByLabel("Title", { exact: false }).inputValue(),
        "A small, useful experiment",
      );
      assert.equal(
        await page.evaluate(
          () =>
            JSON.parse(localStorage.getItem("imdao.drafts.v1")).drafts.length,
        ),
        5,
      );
    },
  );
  await check(
    "Unsaved navigation and draft replacement can be cancelled; confirmed discard works",
    async () => {
      await page.getByLabel("Title", { exact: false }).fill("An unsaved title");
      page.once("dialog", (d) => d.dismiss());
      await page.getByRole("link", { name: "New idea", exact: true }).click();
      await settle();
      assert.equal(
        await page.getByLabel("Title", { exact: false }).inputValue(),
        "An unsaved title",
      );
      page.once("dialog", (d) => d.dismiss());
      await page.getByRole("link", { name: "Projects", exact: true }).click();
      await settle();
      assert(page.url().includes(scratchId));
      page.once("dialog", (d) => d.accept());
      await page.getByRole("link", { name: "New idea", exact: true }).click();
      await settle();
      assert.equal(
        await page.getByLabel("Title", { exact: false }).inputValue(),
        "",
      );
    },
  );
  await check("Browser Back protects unsaved work", async () => {
    await goto("/ideas");
    await page.getByRole("link", { name: "New idea", exact: true }).click();
    await settle();
    await page.getByLabel("Title", { exact: false }).fill("Keep me");
    page.once("dialog", (d) => d.dismiss());
    await page.goBack();
    await settle();
    assert.equal(
      await page.getByLabel("Title", { exact: false }).inputValue(),
      "Keep me",
    );
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("link", { name: "Your local drafts", exact: true })
      .click();
    await settle();
  });
  await check("Deletion requires confirmation and persists", async () => {
    await goto("/draft/" + scratchId);
    page.once("dialog", (d) => d.dismiss());
    await page
      .getByRole("button", { name: "Delete draft", exact: true })
      .click();
    await settle();
    assert(await page.getByLabel("Title", { exact: false }).isVisible());
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("button", { name: "Delete draft", exact: true })
      .click();
    await settle();
    assert(page.url().endsWith("/drafts"));
    await page.reload();
    assert.equal(
      await page.locator(`a[href="#/draft/${scratchId}"]`).count(),
      0,
    );
  });
  await check(
    "Missing routes and unknown idea/project/decision/draft/template recover",
    async () => {
      for (const route of [
        "/unknown",
        "/ideas/missing",
        "/projects/missing",
        "/vote/missing",
        "/draft/draft-missing",
        "/draft/new?template=missing",
      ]) {
        await goto(route);
        assert(
          await page.getByRole("link", { name: "Back to ideas" }).isVisible(),
        );
      }
    },
  );
  await check(
    "Corrupt stored drafts are preserved until explicit reset",
    async () => {
      await page.evaluate(() =>
        localStorage.setItem("imdao.drafts.v1", "{broken"),
      );
      await goto("/drafts");
      await page.reload();
      assert(await page.getByRole("alert").isVisible());
      assert.equal(
        await page.evaluate(() => localStorage.getItem("imdao.drafts.v1")),
        "{broken",
      );
      page.once("dialog", (d) => d.dismiss());
      await page.getByRole("button", { name: "Reset local drafts" }).click();
      await settle();
      assert.equal(
        await page.evaluate(() => localStorage.getItem("imdao.drafts.v1")),
        "{broken",
      );
      page.once("dialog", (d) => d.accept());
      await page.getByRole("button", { name: "Reset local drafts" }).click();
      await settle();
      assert(
        await page
          .getByRole("heading", { name: "Your next idea can start here." })
          .isVisible(),
      );
    },
  );
  await check(
    "Storage write failure never claims save; theme remains usable for session",
    async () => {
      const p = await makePage();
      await p.addInitScript(() => {
        Storage.prototype.setItem = function () {
          throw new DOMException("Quota", "QuotaExceededError");
        };
      });
      await p.goto(base + "#/draft/new");
      await p.getByLabel("Title", { exact: false }).fill("Storage failure");
      await p.getByLabel("Problem or opportunity").fill("A problem");
      await p.getByLabel("First step").fill("One step");
      await p.getByRole("button", { name: "Save draft", exact: true }).click();
      await settle();
      assert(await p.getByRole("alert").isVisible());
      assert.equal(
        await p
          .getByText(
            "Saved on this device only. This private draft has not been submitted.",
          )
          .count(),
        0,
      );
      await p.getByRole("button", { name: "Switch to dark theme" }).click();
      await settle();
      assert.equal(await p.locator("html").getAttribute("data-theme"), "dark");
      assert(
        await p
          .getByText("Theme changed for this session.", { exact: false })
          .isVisible(),
      );
      await p.context().close();
    },
  );
  await check("Blocked reads show a recoverable storage error", async () => {
    const p = await makePage();
    await p.addInitScript(() => {
      Storage.prototype.getItem = function () {
        throw new DOMException("Blocked", "SecurityError");
      };
    });
    await p.goto(base + "#/drafts");
    assert(await p.getByRole("alert").isVisible());
    await p.getByRole("button", { name: "Retry loading" }).click();
    await settle();
    assert(await p.getByRole("alert").isVisible());
    await p.context().close();
  });
  await check(
    "Keyboard navigation, visible focus, form activation and skip link",
    async () => {
      await goto();
      await page.keyboard.press("Tab");
      const focused = await page.evaluate(() => ({
        tag: document.activeElement.tagName,
        outline: getComputedStyle(document.activeElement).outlineStyle,
      }));
      assert.equal(focused.outline, "solid");
      await page.locator(".skip-link").focus();
      await page.keyboard.press("Enter");
      await settle();
      assert.equal(
        await page.evaluate(() => document.activeElement.id),
        "main",
      );
      await page.getByRole("link", { name: "New idea", exact: true }).focus();
      await page.keyboard.press("Enter");
      await settle();
      await page.getByLabel("Title", { exact: false }).focus();
      await page.keyboard.type("Keyboard draft");
      await page.keyboard.press("Tab");
      assert.equal(
        await page.evaluate(() => document.activeElement.id),
        "field-category",
      );
      await page
        .getByRole("button", { name: "Save draft", exact: true })
        .focus();
      await page.keyboard.press("Enter");
      await settle();
      assert.equal(
        await page.evaluate(() => document.activeElement.id),
        "field-problem",
      );
      page.once("dialog", (d) => d.accept());
      await page.getByRole("link", { name: "Ideas", exact: true }).click();
      await settle();
    },
  );
  for (const color of ["light", "dark"]) {
    await check(
      `${color}: responsive layout at 320, 375, 768 and 1440; every page without horizontal overflow`,
      async () => {
        await page.evaluate(
          (c) => localStorage.setItem("imdao.theme.v1", c),
          color,
        );
        await page.reload();
        assert.equal(await theme(), color);
        for (const width of [320, 375, 768, 1440]) {
          await page.setViewportSize({ width, height: 1000 });
          for (const route of [
            "/",
            "/projects",
            "/projects/newsletter-pilot",
            "/vote",
            "/vote/policy-example",
            "/treasury",
            "/draft/new",
            "/drafts",
            "/ideas/research-digest",
          ]) {
            await goto(route);
            await noOverflow();
          }
        }
      },
    );
    await check(
      `${color}: rendered contrast and automated accessibility`,
      async () => {
        await goto();
        await measure(color);
        await axe(color + " home desktop");
        await goto("/draft/new");
        await axe(color + " editor");
        await goto("/vote");
        await axe(color + " governance");
        await goto("/treasury");
        await axe(color + " treasury");
      },
    );
    await check(
      `${color}: desktop and mobile screenshots of final export`,
      async () => {
        await page.setViewportSize({ width: 1440, height: 1050 });
        await goto();
        await page.evaluate(() => document.fonts.ready);
        await page.screenshot({
          path: resolve(artifact, `desktop-${color}.png`),
          fullPage: true,
        });
        await page.setViewportSize({ width: 375, height: 812 });
        await goto();
        await page.screenshot({
          path: resolve(artifact, `mobile-${color}.png`),
          fullPage: true,
        });
        await axe(color + " mobile home");
        await page.getByRole("link", { name: "New idea", exact: true }).focus();
        await page.screenshot({
          path: resolve(artifact, `focus-${color}.png`),
        });
        await goto("/draft/new");
        await page.getByLabel("Title", { exact: false }).focus();
        await page.screenshot({
          path: resolve(artifact, `editor-${color}.png`),
        });
      },
    );
  }
  await check("200% text enlargement reflows at 768px", async () => {
    await page.setViewportSize({ width: 768, height: 1000 });
    await goto("/draft/new");
    await page.evaluate(
      () => (document.documentElement.style.fontSize = "200%"),
    );
    await noOverflow();
    await page.evaluate(() => (document.documentElement.style.fontSize = ""));
  });
  await check(
    "Forced-colors focus has a system color and visible perimeter",
    async () => {
      await page.emulateMedia({ forcedColors: "active" });
      await goto();
      await page.getByRole("link", { name: "New idea", exact: true }).focus();
      const s = await page
        .getByRole("link", { name: "New idea", exact: true })
        .evaluate((e) => ({
          width: getComputedStyle(e).outlineWidth,
          style: getComputedStyle(e).outlineStyle,
        }));
      assert.equal(s.width, "3px");
      assert.equal(s.style, "solid");
      await page.emulateMedia({ forcedColors: "none" });
    },
  );
  await check(
    "Unknown draft schema and malformed fields are preserved and rejected",
    async () => {
      const p = await makePage();
      await p.goto(base + "#/drafts");
      const cases = [
        JSON.stringify({ version: 2, drafts: [] }),
        JSON.stringify({
          version: 1,
          drafts: [{ id: "draft-invalid", title: 12 }],
        }),
        JSON.stringify({ version: 1, drafts: [null] }),
      ];
      for (const data of cases) {
        await p.evaluate(
          (data) => localStorage.setItem("imdao.drafts.v1", data),
          data,
        );
        await p.reload();
        await p.getByRole("alert").waitFor();
        assert.equal(
          await p.evaluate(() => localStorage.getItem("imdao.drafts.v1")),
          data,
        );
      }
      await p.context().close();
    },
  );
  await check(
    "Unsaved work is protected on reload and same-route replacement",
    async () => {
      const p = await makePage();
      await p.goto(base + "#/draft/new");
      await p.getByLabel("Title", { exact: false }).fill("Do not lose this");
      p.once("dialog", (d) => d.dismiss());
      await p
        .getByRole("link", { name: "Start a fresh draft", exact: true })
        .click();
      assert.equal(
        await p.getByLabel("Title", { exact: false }).inputValue(),
        "Do not lose this",
      );
      let sawUnload = false;
      p.once("dialog", async (d) => {
        sawUnload = d.type() === "beforeunload";
        await d.dismiss();
      });
      try {
        await p.reload({ timeout: 3000 });
      } catch (error) {
        if (
          !String(error).includes("ERR_ABORTED") &&
          !String(error).includes("Timeout")
        )
          throw error;
      }
      assert(sawUnload);
      assert.equal(
        await p.getByLabel("Title", { exact: false }).inputValue(),
        "Do not lose this",
      );
      await p.context().close();
    },
  );
  await check(
    "No runtime console errors or unexpected failed resource loads",
    async () => {
      assert.deepEqual(consoleErrors, []);
      assert.deepEqual(resources, []);
    },
  );
} finally {
  await writeFile(
    resolve(artifact, "interaction-results.json"),
    JSON.stringify(
      {
        browser: "Chromium via Playwright",
        basePath: "/preview/",
        results,
        contrast,
        audits,
        consoleErrors,
        failedResources: resources,
      },
      null,
      2,
    ) + "\n",
  );
  await browser.close();
  await new Promise((r) => server.close(r));
}
console.log(
  `${results.filter((x) => x.result === "PASS").length}/${results.length} checks passed`,
);
if (results.some((x) => x.result === "FAIL")) process.exitCode = 1;
