import React, { Fragment, ReactNode, useEffect, useRef } from "react";
import { useAtom } from "jotai";
import { useQueryClient } from "@tanstack/react-query";
import { appPage } from "@/store/jotai.ts";
import { useDatabase } from "@/hooks/useDatabase.ts";

interface SessionGateProps {
  /** Tree rendered for a signed-in staff member; remounted when the user changes */
  authenticated: ReactNode;
  /** Tree rendered without a staff session (login screen) */
  anonymous: ReactNode;
}

/**
 * Keeps the app session (`appPage.user`) and the database session in step.
 *
 * Without a staff session the database rejects every query, so the providers
 * that load data, run timers or subscribe to live queries only mount once
 * someone is signed in, and remount for each new user.
 */
export const SessionGate: React.FC<SessionGateProps> = ({ authenticated, anonymous }) => {
  const { authUserId, signOut } = useDatabase();
  const [page, setPage] = useAtom(appPage);
  const queryClient = useQueryClient();
  const userId = page.user?.id ? String(page.user.id) : undefined;
  const previousUserId = useRef(userId);

  // A token left over from a login that never entered the app (e.g. reload during clock-in).
  useEffect(() => {
    if (authUserId && !userId) {
      void signOut();
    }
    // Only on startup: later this state is a login in progress.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The app ended the session (logout, clock-out, idle logout): end it in the database too.
  useEffect(() => {
    if (previousUserId.current !== userId) {
      queryClient.clear();
      if (previousUserId.current && !userId && authUserId) {
        void signOut();
      }
    }
    previousUserId.current = userId;
  }, [userId, authUserId, signOut, queryClient]);

  // The database session is gone (expired or missing token): back to the login screen.
  useEffect(() => {
    if (!authUserId && page.user) {
      setPage(prev => ({
        ...prev,
        page: 'Login',
        user: undefined,
        locked: false,
        lockedBy: undefined,
      }));
    }
  }, [authUserId, page.user, setPage]);

  if (authUserId && userId) {
    return <Fragment key={userId}>{authenticated}</Fragment>;
  }

  return <>{anonymous}</>;
};
