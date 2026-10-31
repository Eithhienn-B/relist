// Playwright MCP phase 2: two users chat in real time, a third can't see the thread, the nudge fires, a block stops delivery.
async (page) => {
  const listing = "fafe7f19-67cb-4ccf-a389-a98ab959fce4";
  const dir = "C:/Users/ecmb1/projects/relist/e2e";
  const browser = page.context().browser();
  const open = async (name) => {
    const ctx = await browser.newContext({ storageState: `${dir}/.state-${name}.json`, viewport: { width: 420, height: 860 } });
    return ctx.newPage();
  };
  const [alice, bob, carol] = [await open("alice"), await open("bob"), await open("carol")];
  const log = [];
  const check = (ok, what) => { log.push(`${ok ? "PASS" : "FAIL"} ${what}`); };
  const bubble = (p, text) => p.getByRole("log").getByText(text);

  // Bob starts the thread from the listing page.
  await bob.goto(`http://localhost:3000/listings/${listing}`);
  await bob.getByRole("button", { name: "Message seller" }).click();
  await bob.waitForURL(/\/messages\/[0-9a-f-]{36}$/);
  const threadUrl = bob.url();
  check(await bob.getByText("Before you meet").isVisible(), "first thread shows safety tips");
  await bob.screenshot({ path: `${dir}/shots/1-bob-empty-thread.png` });

  await alice.goto(threadUrl);
  await alice.getByRole("textbox", { name: "Message" }).waitFor();

  // Real time: Bob sends, Alice sees it without reloading.
  await bob.getByRole("textbox", { name: "Message" }).fill("Hi! Is the lamp still available?");
  await bob.keyboard.press("Enter");
  const t0 = Date.now();
  await bubble(alice, "Hi! Is the lamp still available?").waitFor({ timeout: 8000 });
  check(true, `alice received bob's message live in ${Date.now() - t0} ms`);

  // Nudge: Alice types a Venmo handle; she's warned before sending, Bob gets the banner.
  const reply = "Yes! Venmo me @alice-lamp and it's yours";
  await alice.getByRole("textbox", { name: "Message" }).fill(reply);
  check(await alice.getByRole("status").filter({ hasText: "Payments stay in ReList" }).isVisible(), "sender sees the nudge before sending");
  check(await alice.getByRole("button", { name: "Send anyway" }).isVisible(), "send button becomes 'Send anyway'");
  await alice.screenshot({ path: `${dir}/shots/2-alice-nudge.png` });
  await alice.getByRole("button", { name: "Send anyway" }).click();
  await bubble(bob, reply).waitFor({ timeout: 8000 });
  check(await bob.getByText("Keep payments in ReList.").isVisible(), "recipient sees the keep-payments banner");
  await bob.screenshot({ path: `${dir}/shots/3-bob-banner.png` });

  // Third member: the thread page 404s, and their inbox is empty.
  await carol.goto(threadUrl);
  check(await carol.getByText(/could not be found|404/i).first().isVisible(), "third member gets a 404 on the thread");
  await carol.goto("http://localhost:3000/messages");
  check(await carol.getByText("No conversations yet.").isVisible(), "third member's inbox is empty");

  // Block: Bob blocks Alice; Alice's next message is refused and never reaches Bob.
  const before = await bob.getByRole("log").getByRole("listitem").count();
  await bob.getByRole("button", { name: "Block" }).click();
  await bob.getByRole("group").getByRole("button", { name: "Block", exact: true }).click();
  await bob.getByText("This conversation has ended.").waitFor();
  check(true, "blocker sees the thread end");
  await alice.getByRole("textbox", { name: "Message" }).fill("hello??");
  await alice.keyboard.press("Enter");
  await alice.getByRole("status").filter({ hasText: "This conversation has ended." }).waitFor({ timeout: 8000 });
  check(true, "blocked user's send is refused");
  await bob.waitForTimeout(2500);
  check((await bob.getByRole("log").getByRole("listitem").count()) === before, "nothing new is delivered after the block");
  check(await bob.getByRole("log").getByText("hello??").count() === 0, "blocked message never appears for the blocker");
  await alice.screenshot({ path: `${dir}/shots/4-alice-blocked.png` });
  await bob.screenshot({ path: `${dir}/shots/5-bob-ended.png` });

  await alice.goto(`http://localhost:3000/listings/${listing}`);
  await bob.goto(`http://localhost:3000/listings/${listing}`);
  check(await bob.getByText(/could not be found|404/i).first().isVisible(), "blocker can no longer see the blocked seller's listing");

  for (const p of [alice, bob, carol]) await p.context().close();
  return { threadUrl, log };
}
