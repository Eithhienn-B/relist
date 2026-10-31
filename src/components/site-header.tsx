import Link from "next/link";
import { LogOut, Plus } from "lucide-react";
import { signOut } from "@/app/auth-actions";
import { Button, buttonVariants } from "@/components/ui/button";

export function SiteHeader({ email }: { email: string }) {
  return (
    <header className="sticky top-0 z-10 border-b bg-background/85 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4">
        <Link href="/" className="text-lg font-semibold tracking-tight">
          Re<span className="text-brand">List</span>
        </Link>
        <nav className="flex items-center gap-1 text-sm">
          <Link href="/" className="rounded-md px-2 py-1 text-muted-foreground hover:text-foreground">Browse</Link>
          <Link href="/messages" className="rounded-md px-2 py-1 text-muted-foreground hover:text-foreground">Messages</Link>
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <span className="hidden text-sm text-muted-foreground sm:inline">{email}</span>
          <Link href="/sell" className={buttonVariants({ size: "sm", className: "press" })}>
            <Plus aria-hidden /> Sell
          </Link>
          <form action={signOut}>
            <Button type="submit" variant="ghost" size="icon-sm" aria-label="Sign out" title="Sign out" className="press">
              <LogOut aria-hidden />
            </Button>
          </form>
        </div>
      </div>
    </header>
  );
}
