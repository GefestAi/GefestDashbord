"use client";

import { ClerkProvider } from "@clerk/nextjs";
import { useEffect, useState, type ReactNode } from "react";

import { isLikelyValidClerkPublishableKey } from "@/auth/clerkKey";
import {
  clearLocalAuthToken,
  getLocalAuthToken,
  isLocalAuthMode,
  setLocalAuthToken,
} from "@/auth/localAuth";
import { LocalAuthLogin } from "@/components/organisms/LocalAuthLogin";
import { getApiBaseUrl } from "@/lib/api-base";

const LOCAL_AUTH_TOKEN_MIN_LENGTH = 50;

async function tryAutoAuthFromUrl(): Promise<boolean> {
  if (typeof window === "undefined") return false;
  const params = new URLSearchParams(window.location.search);
  const token = params.get("token");
  if (!token || token.length < LOCAL_AUTH_TOKEN_MIN_LENGTH) return false;

  let baseUrl: string;
  try {
    baseUrl = getApiBaseUrl();
  } catch {
    return false;
  }

  try {
    const response = await fetch(`${baseUrl}/api/v1/users/me`, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (response.ok) {
      setLocalAuthToken(token);
      // Remove token from URL to avoid it staying in browser history.
      const url = new URL(window.location.href);
      url.searchParams.delete("token");
      window.history.replaceState({}, "", url.toString());
      return true;
    }
  } catch {
    // Network error — fall through to show login form.
  }
  return false;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const localMode = isLocalAuthMode();
  // `checking` is true while we probe a ?token= query param on first render.
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    if (!localMode) {
      clearLocalAuthToken();
      setChecking(false);
      return;
    }
    if (getLocalAuthToken()) {
      setChecking(false);
      return;
    }
    // No stored token — try to auto-authenticate from ?token= URL param.
    tryAutoAuthFromUrl().finally(() => setChecking(false));
  }, [localMode]);

  if (localMode) {
    if (checking) return null;
    if (!getLocalAuthToken()) {
      return <LocalAuthLogin />;
    }
    return <>{children}</>;
  }

  const publishableKey = process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;
  const afterSignOutUrl =
    process.env.NEXT_PUBLIC_CLERK_AFTER_SIGN_OUT_URL ?? "/";

  if (!isLikelyValidClerkPublishableKey(publishableKey)) {
    return <>{children}</>;
  }

  return (
    <ClerkProvider
      publishableKey={publishableKey}
      afterSignOutUrl={afterSignOutUrl}
    >
      {children}
    </ClerkProvider>
  );
}
