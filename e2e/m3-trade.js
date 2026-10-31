// Playwright MCP, Gate 2a part A: offer -> accept -> code -> typed by the seller -> Completed, in three browser contexts.
// Needs sessions from m2-signup.js and the Desk lamp listing (id below) owned by alice.
async (page) => {
  const lamp = "aaaaaaaa-0000-4000-8000-000000000001";
  const dir = "C:/Users/ecmb1/projects/relist/e2e";
  const base = "http://localhost:3000";
  const browser = page.context().browser();
  const open = async (name) => (await browser.newContext({ storageState: `${dir}/.state-${name}.json`, viewport: { width: 420, height: 900 } })).newPage();
  const [alice, bob, carol] = [await open("alice"), await open("bob"), await open("carol")];
  const log = [];
  const check = (ok, what) => log.push(`${ok ? "PASS" : "FAIL"} ${what}`);
  const panel = (p) => p.getByRole("region", { name: "Offer" });
  const startThread = async (p) => {
    await p.goto(`${base}/listings/${lamp}`);
    await p.getByRole("button", { name: "Message seller" }).click();
    await p.waitForURL(/\/messages\/[0-9a-f-]{36}$/);
    return p.url();
  };
  const offer = async (p, amount) => {
    await p.getByLabel("Make an offer").fill(amount);
    await p.getByRole("button", { name: "Send offer" }).click();
    await panel(p).getByText(/offer is with the seller/).waitFor();
  };

  // Carol and Bob both offer on the lamp.
  const carolThread = await startThread(carol);
  await offer(carol, "18");
  const bobThread = await startThread(bob);
  check(await bob.getByLabel("Make an offer").inputValue() === "20", "offer box is prefilled with the asking price");
  await offer(bob, "20");
  check(await bob.getByRole("log").getByText("Offered $20.00").isVisible(), "the offer shows as an event card in the thread");
  await bob.screenshot({ path: `${dir}/shots/m3-1-bob-offered.png` });

  // Alice accepts Bob's; Bob's panel updates live, Carol's offer is declined and the lamp shows on hold to her.
  await alice.goto(bobThread);
  await panel(alice).getByText("The buyer offered $20").waitFor();
  check(true, "seller sees whose move it is");
  await alice.screenshot({ path: `${dir}/shots/m3-2-alice-accept.png` });
  await panel(alice).getByRole("button", { name: "Accept" }).click();
  await panel(bob).getByText(/Accepted at \$20/).waitFor({ timeout: 8000 });
  check(true, "buyer's panel flips to Accepted live");
  await bob.screenshot({ path: `${dir}/shots/m3-3-bob-accepted.png` });
  await carol.reload();
  check(await carol.getByRole("log").getByText("Declined: the seller accepted another offer").isVisible(), "the other buyer's offer is declined");
  check(await panel(carol).getByText("On hold for another buyer").isVisible(), "the other buyer sees the listing on hold");
  check(await carol.getByText("On hold ·").isVisible(), "thread header still shows the listing (pending) for the other buyer");
  await carol.screenshot({ path: `${dir}/shots/m3-4-carol-on-hold.png` });

  // The buyer's code screen.
  await panel(bob).getByRole("link", { name: "Show handoff code" }).click();
  await bob.waitForURL(/\/offers\//);
  const offerUrl = bob.url();
  await bob.getByRole("img", { name: "Handoff QR code" }).waitFor();
  await bob.waitForFunction(() => /\d{3}\s?\d{3}/.test(document.querySelector("[data-testid=handoff-digits]")?.textContent ?? ""));
  const code = (await bob.getByTestId("handoff-digits").textContent()).replace(/\D/g, "");
  check(/^\d{6}$/.test(code), "buyer sees a QR and 6 digits");
  check(await bob.getByText("Only show this in person.").isVisible(), "never-share warning is next to the code");
  await bob.screenshot({ path: `${dir}/shots/m3-5-bob-code.png` });

  // A third user: 404 on the thread and on the offer.
  await carol.goto(bobThread);
  check(await carol.getByText(/could not be found|404/i).first().isVisible(), "third user gets a 404 on the buyer's thread");
  await carol.goto(offerUrl);
  check(await carol.getByText(/could not be found|404/i).first().isVisible(), "third user gets a 404 on the offer");

  // The seller: a wrong code fails, the right one completes it, and both screens say Completed.
  await alice.goto(offerUrl);
  const wrong = code === "000000" ? "111111" : "000000";
  await alice.getByLabel(/6 digits/).fill(wrong);
  await alice.getByRole("button", { name: "Confirm" }).click();
  await alice.getByRole("alert").filter({ hasText: "didn't match" }).waitFor();
  check(true, "a wrong code is refused with a clear message");
  // Re-read the code in case the 30 s window turned over.
  const fresh = (await bob.getByTestId("handoff-digits").textContent()).replace(/\D/g, "");
  await alice.getByLabel(/6 digits/).fill(fresh);
  await alice.screenshot({ path: `${dir}/shots/m3-6-alice-typed.png` });
  await alice.getByRole("button", { name: "Confirm" }).click();
  await alice.getByText("Completed", { exact: true }).waitFor({ timeout: 8000 });
  check(true, "seller sees Completed");
  await bob.getByText("Completed", { exact: true }).waitFor({ timeout: 8000 });
  check(true, "buyer's code screen flips to Completed live");
  await alice.screenshot({ path: `${dir}/shots/m3-7-alice-completed.png` });
  await bob.screenshot({ path: `${dir}/shots/m3-8-bob-completed.png` });

  await bob.goto(bobThread);
  check(await bob.getByRole("log").getByText("Handoff confirmed. Sold for $20.00").isVisible(), "the completed event is in the thread");
  check(await bob.getByText("Sold ·").isVisible(), "the listing shows as sold in the buyer's thread");
  await carol.goto(carolThread);
  check(await panel(carol).getByText("This item sold").isVisible(), "the other buyer sees it sold");

  for (const p of [alice, bob, carol]) await p.context().close();
  return { bobThread, offerUrl, log };
}
