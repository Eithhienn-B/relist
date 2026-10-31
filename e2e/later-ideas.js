// Playwright MCP: later ideas. Edit (incl. prohibited-items refusal), take down, read receipts live,
// block -> "ended" live for the other side, unblock and pick the chat back up, admin filters/paging.
// Needs sessions from m2-signup.js, alice as an admin, and the two seeded listings below owned by alice.
async (page) => {
  const lamp = "aaaaaaaa-0000-4000-8000-000000000001";
  const shelf = "aaaaaaaa-0000-4000-8000-000000000002";
  const dir = "C:/Users/ecmb1/projects/relist/e2e";
  const base = "http://localhost:3000";
  const browser = page.context().browser();
  const open = async (name) => (await browser.newContext({ storageState: `${dir}/.state-${name}.json`, viewport: { width: 420, height: 900 } })).newPage();
  const [alice, bob] = [await open("alice"), await open("bob")];
  const log = [];
  const check = (ok, what) => log.push(`${ok ? "PASS" : "FAIL"} ${what}`);

  // Edit: a normal edit saves; a prohibited word is refused with the reason.
  await alice.goto(`${base}/listings/${lamp}`);
  await alice.getByRole("link", { name: "Edit or take down" }).click();
  await alice.getByLabel("Title").fill("Desk lamp, warm white");
  await alice.getByRole("button", { name: "Save changes" }).click();
  await alice.waitForURL(`${base}/listings/${lamp}`);
  check(await alice.getByRole("heading", { name: "Desk lamp, warm white" }).isVisible(), "seller edits the title");
  await alice.goto(`${base}/listings/${lamp}/edit`);
  await alice.getByLabel("Title").fill("Desk lamp and beer");
  await alice.getByRole("button", { name: "Save changes" }).click();
  await alice.getByRole("alert").filter({ hasText: "Alcohol isn't allowed" }).waitFor({ timeout: 10000 });
  check(true, "an edit re-runs the prohibited-items check");
  await alice.screenshot({ path: `${dir}/shots/later-1-edit-refused.png` });

  // Take down.
  await alice.goto(`${base}/listings/${shelf}/edit`);
  await alice.getByRole("button", { name: "Take down listing" }).click();
  await alice.getByRole("button", { name: "Yes, take it down" }).click();
  await alice.waitForURL(`${base}/`);
  await bob.goto(`${base}/listings/${shelf}`);
  check(await bob.getByText(/could not be found|404/i).first().isVisible(), "a taken-down listing is gone for buyers");

  // Read receipts, live.
  await bob.goto(`${base}/listings/${lamp}`);
  await bob.getByRole("button", { name: "Message seller" }).click();
  await bob.waitForURL(/\/messages\/[0-9a-f-]{36}$/);
  const thread = bob.url();
  await bob.getByRole("textbox", { name: "Message" }).fill("Is the lamp still around?");
  await bob.keyboard.press("Enter");
  await bob.getByRole("log").getByText("Is the lamp still around?").waitFor();
  check(await bob.getByText("Seen").count() === 0, "not marked seen before the seller opens it");
  await alice.goto(thread);
  await bob.getByText("Seen").waitFor({ timeout: 8000 });
  check(true, "buyer sees 'Seen' live once the seller opens the thread");
  await bob.screenshot({ path: `${dir}/shots/later-2-seen.png` });

  // Block: the other side's composer goes away live, without trying to send.
  await alice.getByRole("button", { name: "Block" }).click();
  await alice.getByRole("group").getByRole("button", { name: "Block", exact: true }).click();
  await bob.getByRole("log").getByText("This conversation has ended.").waitFor({ timeout: 8000 });
  check(await bob.getByRole("textbox", { name: "Message" }).count() === 0, "blocked side sees the thread end live (composer gone)");
  await bob.screenshot({ path: `${dir}/shots/later-3-ended-live.png` });

  // Unblock: only the blocker has the button; the chat stays closed until the buyer messages from the listing.
  check(await bob.getByRole("button", { name: "Unblock" }).count() === 0, "the blocked person has no unblock button");
  await alice.getByRole("button", { name: "Unblock" }).click();
  await alice.getByText(/Unblocked\. This chat stays closed/).waitFor();
  check(true, "blocker unblocks; nothing reopens by itself");
  await bob.goto(`${base}/listings/${lamp}`);
  await bob.getByRole("button", { name: "Message seller" }).click();
  await bob.waitForURL(thread);
  await bob.getByRole("textbox", { name: "Message" }).waitFor();
  check(true, "the buyer picks the chat back up from the listing");

  // Admin queue: filters and paging controls.
  await alice.goto(`${base}/admin?status=all`);
  check(await alice.getByLabel("status").inputValue() === "all", "admin queue keeps the status filter");
  check(await alice.getByRole("button", { name: "Filter" }).isVisible(), "admin queue has filters");
  await bob.goto(`${base}/admin`);
  check(await bob.getByText(/could not be found|404/i).first().isVisible(), "non-admin still gets a 404");

  for (const p of [alice, bob]) await p.context().close();
  return { log };
}
