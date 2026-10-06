import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { faArrowLeft, faBackspace, faCircle, faClock } from "@fortawesome/free-solid-svg-icons";
import {faCircle as circleRegular} from '@fortawesome/free-regular-svg-icons';
import {useEffect, useLayoutEffect, useMemo, useState} from "react";
import { useAtom } from "jotai";
import { appPage } from "@/store/jotai.ts";
import { cn } from "@/lib/utils.ts";
import { useDB } from "@/api/db/db.ts";
import { User } from "@/api/model/user.ts";
import {useNavigate, useLocation} from "react-router";
import {MENU} from "@/routes/posr.ts";
import { Modal } from "@/components/common/react-aria/modal.tsx";
import { Button } from "@/components/common/input/button.tsx";
import { Tables } from "@/api/db/tables.ts";
import { toast } from "sonner";
import { getUserModules } from "@/lib/access.rules.ts";
import { UserRole } from "@/api/model/user_role.ts";
import { Input } from "@/components/common/input/input.tsx";
import { clockIn as laborClockIn } from "@/lib/labor-engine/attendance/attendance.service.ts";
import { ensureEmployeeForUser } from "@/lib/labor-engine/employee.resolver.ts";
import { useTranslation } from "react-i18next";
import i18n from "@/lib/i18n.ts";
import { DocumentTitle } from "@/components/common/document-title.tsx";
import { useDatabase } from "@/hooks/useDatabase.ts";
import { fetchLoginDirectory, LoginDirectoryEntry, TooManyAttemptsError, userKey, verifyCredentials } from "@/api/db/auth.ts";

export const Login = () => {
  const db = useDB();
  const { client, isConnected, signIn, signOut } = useDatabase();
  const { t } = useTranslation('auth');

  const [code, setCode] = useState('');
  const [loginMethod, setLoginMethod] = useState<'pin'|'form'>('pin');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [page, setPage] = useAtom(appPage);
  const [error, setError] = useState(false);
  const [showClockInModal, setShowClockInModal] = useState(false);
  const [pendingUser, setPendingUser] = useState<User | null>(null);
  const [directory, setDirectory] = useState<LoginDirectoryEntry[]>([]);
  const [selectedKey, setSelectedKey] = useState<string | undefined>();

  // While locked only the user who locked the terminal can open it again.
  const lockedKey = page.locked && page.lockedBy?.id ? userKey(page.lockedBy.id) : undefined;
  const pinUserKey = lockedKey ?? selectedKey;
  const pinUser = useMemo(
    () => directory.find(entry => entry.key === pinUserKey),
    [directory, pinUserKey],
  );

  useEffect(() => {
    if (!isConnected) return;
    let cancelled = false;
    fetchLoginDirectory(client)
      .then(entries => {
        if (!cancelled) setDirectory(entries);
      })
      .catch(error => console.error('Could not load login names', error));
    return () => {
      cancelled = true;
    };
  }, [client, isConnected]);

  const navigation = useNavigate();
  const location = useLocation();

  const onClear = () => {
    setCode('');
  }

  const onBack = () => {
    setCode(prev => prev.slice(0, prev.length - 1));
  }

  const onKey = (key: string) => {
    if(code.trim().length <= 3){
      setCode(code + key);
    }
  }

  // `subject` is the user's record key for PIN login, the username for form login.
  const checkLogin = async (subject: string, pass: string, method: 'pin'|'form') => {
    if ((method === 'pin' && subject && pass.trim().length === 4) || (method === 'form' && subject.trim() && pass.trim())) {
      let loggedInUser: any;
      try {
        if (page.locked) {
          // Unlocking: check the credentials on a separate connection so a
          // wrong user can't take over this terminal's session.
          loggedInUser = await verifyCredentials(subject, pass, method);
        } else {
          await signIn(subject, pass, method);
          [loggedInUser] = await db.query(`SELECT * FROM ONLY $auth FETCH user_role, user_shift`);
        }
      } catch (e) {
        if (e instanceof TooManyAttemptsError) {
          toast.error(t('login.tooManyAttempts'));
        }
        denyLogin();
        return false;
      }

      if(loggedInUser){
        const roleId = typeof loggedInUser.user_role === "object" ? loggedInUser.user_role?.id : loggedInUser.user_role;
        let fetchedRole: UserRole | undefined;

        if (roleId) {
          const [roleRecords]: any = await db.query(`SELECT * FROM ${Tables.user_roles} WHERE id = $roleId AND deleted_at = none LIMIT 1`, {
            roleId,
          });
          fetchedRole = roleRecords?.[0];
        }

        const normalizedUser = {
          ...loggedInUser,
          user_role: fetchedRole || loggedInUser.user_role,
          roles: fetchedRole
            ? [...new Set(fetchedRole.roles || [])]
            : getUserModules(loggedInUser),
        };

        if(page.locked && String(page.lockedBy?.id) !== String(loggedInUser.id)){
          denyLogin();
          return false;
        }

        // Check for active time entry
        const timeEntryCheck: any = await db.query(`SELECT * from ${Tables.time_entries} where user = $userId and clock_out = NONE and platform = $platform`, {
          userId: loggedInUser.id,
          platform: 'web'
        });

        if(timeEntryCheck[0].length === 0){
          // No active time entry, show clock-in modal
          setPendingUser(normalizedUser);
          setShowClockInModal(true);
        } else {
          // Active time entry exists, proceed with login
          allowLogin(normalizedUser);
        }
      }else{
        denyLogin();
      }
    }
  }

  const allowLogin = (user: User) => {
    setPage(prev => ({
      ...prev,
      page: 'Menu',
      locked: false,
      lockedBy: undefined,
      user: user
    }));

    setCode('');
    setSelectedKey(undefined);
    setUsername('');
    setPassword('');
    setShowClockInModal(false);
    setPendingUser(null);

    // redirect to menu
    navigation(MENU);
  }

  const handleClockIn = async () => {
    if(!pendingUser) return;

    try {
      const employee = await ensureEmployeeForUser(db, pendingUser);
      await laborClockIn(db, {
        user: pendingUser,
        employeeId: employee.id,
        platform: 'web',
        shiftTemplateId: pendingUser.user_shift?.id,
      });

      toast.success(i18n.t('auth:clockIn.success'));
      allowLogin(pendingUser);
    } catch (error) {
      toast.error(i18n.t('auth:clockIn.failed'));
      console.error(error);
    }
  }

  const denyLogin = () => {
    setCode('');
    setPassword('');
    setError(true);
  }

  useEffect(() => {
    if (loginMethod === 'pin' && pinUserKey) {
      checkLogin(pinUserKey, code, 'pin');
    }
  }, [code]);

  useEffect(() => {
    if(error){
      setTimeout(() => setError(false), 400);
    }
  }, [error]);

  useLayoutEffect(() => {
    if(page.user && !page.locked){
      const from = (location.state as { from?: { pathname: string; search?: string } })?.from;
      const returnPath = from ? `${from.pathname}${from.search ?? ''}` : MENU;
      navigation(returnPath, { replace: true });
    }
  }, [page.user, page.locked, location.state, navigation]);

  return (
    <div className="relative">
      <DocumentTitle parts={[t('login.title')]} />
      <div className="bg-neutral-900 flex justify-center items-center h-screen flex-col gap-8">
        <h4 className="text-4xl text-neutral-100">{t('login.title')}</h4>
        <div className="flex gap-3">
          <button
            className={cn(
              "w-56 border-2 transition-all duration-150 btn btn-filled lg",
              loginMethod === 'pin'
                ? "!bg-warning-500 text-black border-warning-500"
                : "!bg-black text-white"
            )}
            onClick={() => {
              setLoginMethod('pin');
              setError(false);
              setUsername('');
              setPassword('');
              setCode('');
              setSelectedKey(undefined);
            }}
          >
            {t('login.pin')}
          </button>
          <button
            className={cn(
              "w-56 border-2 transition-all duration-150 btn btn-filled lg",
              loginMethod === 'form'
                ? "!bg-warning-500 text-black border-warning-500"
                : "!bg-black text-white"
            )}
            onClick={() => {
              setLoginMethod('form');
              setError(false);
              setUsername('');
              setPassword('');
              setCode('');
              setSelectedKey(undefined);
            }}
          >
            {t('login.form')}
          </button>
        </div>
        {page.locked && (
          <div className="alert alert-warning">{t('login.systemLocked', {
            name: `${page?.lockedBy?.first_name ?? ''} ${page?.lockedBy?.last_name ?? ''}`.trim()
          })}</div>
        )}
        {loginMethod === 'pin' && !pinUserKey && (
          <div className="flex flex-col items-center gap-4 w-full max-w-[640px] px-4">
            <div className="text-neutral-300 text-lg">{t('login.whoAreYou')}</div>
            {directory.length === 0 ? (
              <div className="text-neutral-400 text-sm">{t('login.noPinUsers')}</div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 w-full max-h-[50vh] overflow-y-auto">
                {directory.map(entry => (
                  <button
                    key={entry.key}
                    type="button"
                    className="btn btn-filled lg !bg-neutral-800 text-white border-2 border-neutral-700 hover:border-warning-500 truncate"
                    onClick={() => {
                      setCode('');
                      setError(false);
                      setSelectedKey(entry.key);
                    }}
                  >
                    {`${entry.first_name ?? ''} ${entry.last_name ?? ''}`.trim()}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
        {loginMethod === 'pin' && pinUserKey && (
          <>
            <div className="flex items-center gap-3 text-neutral-100 text-xl">
              {!lockedKey && (
                <button
                  type="button"
                  className="size-10 rounded-full text-neutral-300 hover:bg-neutral-800 transition-colors"
                  aria-label={t('login.notYou')}
                  title={t('login.notYou')}
                  onClick={() => {
                    setSelectedKey(undefined);
                    setCode('');
                    setError(false);
                  }}
                >
                  <FontAwesomeIcon icon={faArrowLeft}/>
                </button>
              )}
              <span>{pinUser ? `${pinUser.first_name ?? ''} ${pinUser.last_name ?? ''}`.trim() : ''}</span>
            </div>
            <div className={
              cn(
                "flex gap-3 text-neutral-100",
                error && 'login-error'
              )
            }>
              <FontAwesomeIcon size="lg" icon={code.trim().length >= 1 ? faCircle : circleRegular} />
              <FontAwesomeIcon size="lg" icon={code.trim().length >= 2 ? faCircle : circleRegular} />
              <FontAwesomeIcon size="lg" icon={code.trim().length >= 3 ? faCircle : circleRegular} />
              <FontAwesomeIcon size="lg" icon={code.trim().length === 4 ? faCircle : circleRegular} />
            </div>
            <div className="wrapper w-[400px]">
              <div className="grid grid-cols-3 gap-2 sm:gap-5 place-items-center">
                <button type="button" onClick={() => onKey('1')} className="btn-login">1</button>
                <button type="button" onClick={() => onKey('2')} className="btn-login">2</button>
                <button type="button" onClick={() => onKey('3')} className="btn-login">3</button>
                <button type="button" onClick={() => onKey('4')} className="btn-login">4</button>
                <button type="button" onClick={() => onKey('5')} className="btn-login">5</button>
                <button type="button" onClick={() => onKey('6')} className="btn-login">6</button>
                <button type="button" onClick={() => onKey('7')} className="btn-login">7</button>
                <button type="button" onClick={() => onKey('8')} className="btn-login">8</button>
                <button type="button" onClick={() => onKey('9')} className="btn-login">9</button>
                <button type="button" onClick={onBack} className="btn-login danger"><FontAwesomeIcon icon={faBackspace}/>
                </button>
                <button type="button" onClick={() => onKey('0')} className="btn-login">0</button>
                <button type="button" onClick={onClear} className="btn-login danger">C</button>
              </div>
            </div>
          </>
        )}
        {loginMethod === 'form' && (
          <form
            className="w-[400px] flex flex-col gap-3"
            onSubmit={async (event) => {
              event.preventDefault();
              await checkLogin(username, password, 'form');
            }}
          >
            <div>
              <label className="text-white" htmlFor="username">{t('login.username')}</label>
              <Input
                id="username"
                value={username}
                onChange={(event) => setUsername(event.target.value)}
              />
            </div>
            
            <div>
              <label className="text-white" htmlFor="password">{t('login.password')}</label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </div>
            <Button type="submit" variant="primary">{t('login.submit')}</Button>
          </form>
        )}
        {error && loginMethod === 'form' && (
          <div className="text-danger-500 text-sm">{t('login.invalidCredentials')}</div>
        )}
      </div>
      <div className="size-[100px] bg-warning-500/10 absolute top-10 right-[30%] rounded-full pointer-events-none transition-all blur-lg"></div>
      <div className="size-[200px] bg-primary-500/10 animate-bounce absolute top-20 left-[20%] rounded-full pointer-events-none transition-all blur-2xl"></div>
      <div className="size-[200px] bg-white/20 absolute bottom-[100px] transition-all right-24 pointer-events-none rotate-45 blur-2xl"></div>
      <div className="size-[200px] bg-[tomato]/20 absolute bottom-[30%] transition-all left-[150px] pointer-events-none blur-2xl"></div>

      {showClockInModal && (
        <Modal
          open={showClockInModal}
          onClose={() => {
            setShowClockInModal(false);
            setPendingUser(null);
            setCode('');
            if (!page.locked) {
              // Signed in to the database but never entered the app.
              void signOut();
            }
          }}
          title={t('clockIn.title')}
          shouldCloseOnOverlayClick={false}
          shouldCloseOnEsc={false}
        >
          <div className="flex flex-col gap-4 items-center">
            <div className="text-lg alert alert-danger">
              {t('clockIn.message')}
            </div>
            <div className="flex gap-2">
              <Button
                variant="primary"
                onClick={handleClockIn}
                icon={faClock}
                size="xl"
              >
                {t('clockIn.action')}
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
