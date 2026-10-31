"use client";

import { useState, useTransition } from "react";
import { Loader2, MessageCircle } from "lucide-react";
import { startThread } from "@/app/messages/actions";
import { Button } from "@/components/ui/button";

export function MessageSeller({ listingId }: { listingId: string }) {
  const [error, setError] = useState<string>();
  const [pending, start] = useTransition();
  return (
    <div className="mt-6">
      <Button size="lg" className="press w-full" disabled={pending}
        onClick={() => start(async () => setError(await startThread(listingId)))}>
        {pending ? <Loader2 aria-hidden className="animate-spin" /> : <MessageCircle aria-hidden />} Message seller
      </Button>
      {error && <p role="alert" className="mt-2 text-sm text-destructive">{error}</p>}
    </div>
  );
}
