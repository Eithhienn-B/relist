// Playwright MCP phase 1: sign up three users through the real OTP flow and save their sessions.
async (page) => {
  const browser = page.context().browser();
  const run = Date.now().toString(36);
  const users = {};
  for (const name of ["alice", "bob", "carol"]) {
    const email = `e2e-${name}-${run}@purdue.edu`;
    const ctx = await browser.newContext();
    await ctx.clearCookies();
    const p = await ctx.newPage();
    await p.goto("http://localhost:3000/login");
    await p.fill("#email", email);
    await p.getByRole("button", { name: "Send code" }).click();
    await p.locator("#code").waitFor();
    let code;
    for (let i = 0; i < 20 && !code; i++) {
      const res = await p.request.get(`http://127.0.0.1:54324/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
      const { messages } = await res.json();
      if (messages?.length) {
        const msg = await (await p.request.get(`http://127.0.0.1:54324/api/v1/message/${messages[0].ID}`)).json();
        code = (msg.Text.match(/\b\d{6}\b/) || [])[0];
      }
      if (!code) await p.waitForTimeout(500);
    }
    await p.fill("#code", code);
    await p.getByRole("button", { name: "Sign in" }).click();
    await p.waitForURL("**/onboarding");
    await p.getByRole("checkbox").click();
    await p.getByRole("button", { name: "Finish sign-up" }).click();
    await p.waitForURL((u) => !u.pathname.startsWith("/onboarding"));
    await ctx.storageState({ path: `C:/Users/ecmb1/projects/relist/e2e/.state-${name}.json` });
    users[name] = email;
    await ctx.close();
  }
  return users;
}
