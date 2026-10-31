"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { sendCode, verifyCode, type LoginState } from "./actions";

const initial: LoginState = { step: "email", email: "" };

export default function LoginPage() {
  const [emailState, emailAction, sending] = useActionState(sendCode, initial);
  const [codeState, codeAction, verifying] = useActionState(verifyCode, initial);
  const onCodeStep = emailState.step === "code";

  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <p className="text-sm font-semibold tracking-tight text-muted-foreground">ReList</p>
          <CardTitle className="text-2xl">{onCodeStep ? "Check your inbox" : "Buy and sell on campus"}</CardTitle>
          <CardDescription>
            {onCodeStep
              ? `We sent a 6-digit code to ${emailState.email}.`
              : "Students only. Sign in with your school email."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {!onCodeStep ? (
            <form action={emailAction} className="grid gap-3">
              <Label htmlFor="email">School email</Label>
              <Input id="email" name="email" type="email" autoComplete="email" placeholder="you@purdue.edu"
                defaultValue={emailState.email} required aria-describedby="email-error" />
              {emailState.error && <p id="email-error" role="alert" className="text-sm text-destructive">{emailState.error}</p>}
              <Button type="submit" disabled={sending}>{sending ? "Sending…" : "Send code"}</Button>
            </form>
          ) : (
            <form action={codeAction} className="grid gap-3">
              <input type="hidden" name="email" value={emailState.email} />
              <Label htmlFor="code">6-digit code</Label>
              <Input id="code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}"
                maxLength={6} required autoFocus aria-describedby="code-error" className="tracking-[0.4em]" />
              {codeState.error && <p id="code-error" role="alert" className="text-sm text-destructive">{codeState.error}</p>}
              <Button type="submit" disabled={verifying}>{verifying ? "Checking…" : "Sign in"}</Button>
              {/* Full reload resets both action states back to the email step. */}
              <a href="/login" className="text-center text-sm text-muted-foreground underline-offset-4 hover:underline">
                Use a different email
              </a>
            </form>
          )}
        </CardContent>
      </Card>
    </main>
  );
}
