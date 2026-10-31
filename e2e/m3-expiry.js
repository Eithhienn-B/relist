// Playwright MCP, Gate 2a part B: pasting the handoff code into chat is refused; then (after the SQL step in
// the Gate 2a note moves expires_at back and runs the job) run part C with PART = "C" to check the listing is released.
async (page) => {
  const PART = "B";
  const shelf = "aaaaaaaa-0000-4000-8000-000000000002";
  const dir = "C:/Users/ecmb1/projects/relist/e2e";
  const base = "http://localhost:3000";
  const browser = page.context().browser();
  const open = async (name) => (await browser.newContext({ storageState: `${dir}/.state-${name}.json`, viewport: { width: 420, height: 900 } })).newPage();
  const [alice, bob, carol] = [await open("alice"), await open("bob"), await open("carol")];
  const log = [];
  const check = (ok, what) => log.push(`${ok ? "PASS" : "FAIL"} ${what}`);
  const panel = (p) => p.getByRole("region", { name: "Offer" });

  await bob.goto(`${base}/listings/${shelf}`);
  await bob.getByRole("button", { name: "Message seller" }).click();
  await bob.waitForURL(/\/messages\/[0-9a-f-]{36}$/);
  const thread = bob.url();

  if (PART === "B") {
    await bob.getByLabel("Make an offer").fill("30");
    await bob.getByRole("button", { name: "Send offer" }).click();
    await alice.goto(thread);
    await panel(alice).getByRole("button", { name: "Accept" }).click();
    await panel(bob).getByRole("link", { name: "Show handoff code" }).waitFor({ timeout: 8000 });
    await panel(bob).getByRole("link", { name: "Show handoff code" }).click();
    await bob.waitForFunction(() => /\d{3}\s?\d{3}/.test(document.querySelector("[data-testid=handoff-digits]")?.textContent ?? ""));
    const code = (await bob.getByTestId("handoff-digits").textContent()).replace(/\D/g, "");
    const offerUrl = bob.url();

    // The buyer pastes the code into chat (what a scammer would ask for): refused, never delivered, and burned.
    await bob.goto(thread);
    await bob.getByRole("textbox", { name: "Message" }).fill(`here you go: ${code}`);
    await bob.keyboard.press("Enter");
    await bob.getByRole("alert").filter({ hasText: "Not sent: that's a handoff code" }).waitFor({ timeout: 10000 });
    check(true, "pasting the code into chat is refused");
    await bob.screenshot({ path: `${dir}/shots/m3-9-bob-code-refused.png` });
    await alice.waitForTimeout(1500);
    check(await alice.getByRole("log").getByText(code).count() === 0, "the code never reaches the seller's chat");
    await alice.goto(offerUrl);
    await alice.getByLabel(/6 digits/).fill(code);
    await alice.getByRole("button", { name: "Confirm" }).click();
    await alice.getByRole("alert").filter({ hasText: "didn't match" }).waitFor();
    check(true, "the leaked code is dead: the seller can't redeem it");
    await carol.goto(`${base}/listings/${shelf}`);
    check(await carol.getByText(/could not be found|404/i).first().isVisible(), "a third user can't see the listing while it's on hold");
  } else {
    await bob.reload();
    check(await bob.getByRole("log").getByText(/Expired: no handoff in time/).isVisible(), "the expiry event shows in the thread");
    check(await panel(bob).getByText("Make an offer").isVisible(), "the listing is released: the buyer can offer again");
    await bob.screenshot({ path: `${dir}/shots/m3-10-bob-expired.png` });
    await carol.goto(`${base}/listings/${shelf}`);
    check(await carol.getByRole("button", { name: "Message seller" }).isVisible(), "the released listing is back for everyone");
  }
  for (const p of [alice, bob, carol]) await p.context().close();
  return { thread, log };
}
