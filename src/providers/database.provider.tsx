import React, { createContext, useContext, useEffect, useMemo, useCallback, useRef, useState, ReactNode } from "react";
import { useMutation } from "@tanstack/react-query";
import { Surreal } from "surrealdb";
import { DB_REST_DB, DB_REST_NS, withApi } from "@/api/db/settings.ts";
import { fetchAuthUserId, LoginMethod, readStoredToken, signInUser, storeToken } from "@/api/db/auth.ts";
import { PageLoader } from "@/components/common/loader/page-loader.tsx";
import { useTranslation } from "react-i18next";

export interface DatabaseProviderState {
  /** The Surreal instance */
  client: Surreal;
  /** Whether the connection is pending */
  isConnecting: boolean;
  /** Whether the connection was successfully established */
  isConnected: boolean;
  /** Whether the connection rejected in an error */
  isError: boolean;
  /** The connection error, if present */
  error: unknown;
  /** Connect to the Surreal instance */
  connect: () => Promise<void>;
  /** Close the Surreal instance */
  close: () => Promise<void>;
  /** Record id of the signed-in staff member, undefined while anonymous */
  authUserId?: string;
  /** Signs the connection in as a staff member and returns their record id */
  signIn: (subject: string, password: string, method: LoginMethod) => Promise<string | undefined>;
  /** Drops the staff session; the connection stays open but anonymous */
  signOut: () => Promise<void>;
}

export const DatabaseContext = createContext<DatabaseProviderState | undefined>(undefined);

export interface DatabaseProviderProps {
  children: ReactNode;
  /** Auto connect on component mount, defaults to true */
  autoConnect?: boolean;
}

export const DatabaseProvider: React.FC<DatabaseProviderProps> = ({ 
  children, 
  autoConnect = true 
}) => {
  const { t } = useTranslation('common');
  const [surrealInstance] = useState(() => new Surreal());
  const [authUserId, setAuthUserId] = useState<string | undefined>();
  const authGeneration = useRef(0);

  // React Query mutation for connecting to Surreal
  const {
    mutateAsync: connectMutation,
    isPending,
    isSuccess,
    isError,
    error,
    reset,
  } = useMutation({
    mutationFn: async () => {
      console.log('Connecting to SurrealDB...');
      await surrealInstance.connect(withApi(''), {
        namespace: DB_REST_NS,
        database: DB_REST_DB,
      });
      // Wait for connection to be ready
      await surrealInstance.ready;
      console.log('Successfully connected to SurrealDB');

      // Resume the staff session from before a reload, if its token is still valid.
      const token = readStoredToken();
      let userId: string | undefined;
      if (token) {
        try {
          await surrealInstance.authenticate(token);
          userId = await fetchAuthUserId(surrealInstance);
        } catch {
          storeToken(undefined);
        }
      }
      setAuthUserId(userId);
    },
  });

  // Wrap mutateAsync in a stable callback
  const connect = useCallback(async () => {
    await connectMutation();
  }, [connectMutation]);

  // Wrap close() in a stable callback
  const close = useCallback(async () => {
    await surrealInstance.close();
    reset();
  }, [surrealInstance, reset]);

  const signIn = useCallback(async (subject: string, password: string, method: LoginMethod) => {
    authGeneration.current += 1;
    const token = await signInUser(surrealInstance, subject, password, method);
    storeToken(token);
    const userId = await fetchAuthUserId(surrealInstance);
    setAuthUserId(userId);
    return userId;
  }, [surrealInstance]);

  const signOut = useCallback(async () => {
    const generation = ++authGeneration.current;
    storeToken(undefined);
    setAuthUserId(undefined);
    // Let the signed-in screens finish unmounting (killing their live queries)
    // before the session goes, so those calls aren't rejected as anonymous.
    await new Promise(resolve => setTimeout(resolve, 500));
    if (generation !== authGeneration.current) {
      return; // Someone signed in meanwhile.
    }
    try {
      await surrealInstance.invalidate();
    } catch {
      // Connection already gone; nothing to invalidate.
    }
  }, [surrealInstance]);

  // Auto-connect on mount (if enabled) and cleanup on unmount
  useEffect(() => {
    if (autoConnect) {
      connect();
    }

    return () => {
      reset();
      surrealInstance.close();
    };
  }, [autoConnect, connect, reset, surrealInstance]);

  // Memoize the context value
  const value: DatabaseProviderState = useMemo(
    () => ({
      client: surrealInstance,
      isConnecting: isPending,
      isConnected: isSuccess,
      isError,
      error,
      connect,
      close,
      authUserId,
      signIn,
      signOut,
    }),
    [surrealInstance, isPending, isSuccess, isError, error, connect, close, authUserId, signIn, signOut],
  );

  useEffect(() => {
    const onUnhandledRejection = (event: PromiseRejectionEvent) => {
      const errorName = event?.reason?.name;
      if (errorName === "ConnectionUnavailable" || errorName === "EngineDisconnected") {
        // Intentionally left as a no-op; UI presents reconnect controls.
      }
    };

    window.addEventListener("unhandledrejection", onUnhandledRejection);
    return () => {
      window.removeEventListener("unhandledrejection", onUnhandledRejection);
    };
  }, []);

  if (isError) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-100">
        <div className="text-center max-w-md p-6 bg-danger-50 border border-danger-200 rounded-lg">
          <h2 className="text-xl font-semibold text-danger-800 mb-2">{t('database.connectionError')}</h2>
          <p className="text-danger-600 mb-4">{String(error) || t('database.connectionFailed')}</p>
          <button
            onClick={() => connect()}
            className="px-4 py-2 bg-danger-600 text-white rounded hover:bg-danger-700"
          >
            {t('database.retryConnection')}
          </button>
        </div>
      </div>
    );
  }

  // Show loading state while connecting
  if (isPending || !isSuccess) {
    return <PageLoader/>;
  }

  // Only render children when connection is successful
  return (
    <DatabaseContext.Provider value={value}>
      {children}
    </DatabaseContext.Provider>
  );
};

