-- Name + PIN login.
--
-- PIN users used to sign in with the PIN alone, so the PIN doubled as the
-- username: it was stored in plain text in user.login (readable by all staff),
-- failed attempts could only be throttled for everyone at once, and two staff
-- members with the same PIN could not both log in.
--
-- Now staff tap their name on the login screen and then enter their PIN. The
-- sign-in receives the user's record key, so failures are counted per user,
-- PINs no longer need to be unique, and user.login is only used for
-- username/password (form) accounts.
--
-- The login screen lists names before anyone is signed in. That needs the
-- SurrealDB server to run with --allow-guests; guests can read login_directory
-- (names only) and nothing else, because every other table requires $auth.

-- ------------------------------
-- Names shown on the login screen
-- ------------------------------

DEFINE TABLE OVERWRITE login_directory TYPE NORMAL
  AS SELECT id, first_name, last_name FROM user
    WHERE deleted_at = NONE AND login_method != 'form'
  PERMISSIONS FOR select FULL;

-- ------------------------------
-- Stop storing PINs in plain text
-- ------------------------------

UPDATE user SET login = NONE WHERE login_method != 'form';

-- ------------------------------
-- Sign-in with per-user lockout
-- ------------------------------
-- A user is locked out after 5 failed attempts in 15 minutes or 15 in a day;
-- a successful sign-in clears their failures. The global limit stays as a
-- safety net against guessing across all users at once.

DEFINE FIELD OVERWRITE subject ON login_failure TYPE option<string>;
DEFINE INDEX OVERWRITE login_failure_subject ON login_failure FIELDS subject, at;

DEFINE ACCESS OVERWRITE pos ON DATABASE TYPE RECORD
  SIGNIN {
    LET $global_short = (SELECT count() AS c FROM login_failure WHERE at > time::now() - 1m GROUP ALL)[0].c ?? 0;
    LET $global_long = (SELECT count() AS c FROM login_failure WHERE at > time::now() - 15m GROUP ALL)[0].c ?? 0;
    IF $global_short >= 30 OR $global_long >= 200 {
      THROW "too_many_attempts";
    };

    LET $subject = IF $method = 'form' {
      'login:' + <string> ($login ?? '')
    } ELSE {
      'user:' + <string> ($user ?? '')
    };

    LET $recent = (SELECT count() AS c FROM login_failure
      WHERE subject = $subject AND at > time::now() - 15m GROUP ALL)[0].c ?? 0;
    LET $today = (SELECT count() AS c FROM login_failure
      WHERE subject = $subject AND at > time::now() - 1d GROUP ALL)[0].c ?? 0;
    IF $recent >= 5 OR $today >= 15 {
      THROW "too_many_attempts";
    };

    LET $found = IF $method = 'form' {
      (SELECT * FROM user
        WHERE login = $login AND deleted_at = NONE AND login_method = 'form'
          AND crypto::bcrypt::compare(password, $password) = true
        LIMIT 1)[0]
    } ELSE IF type::is_string($user) AND $user != '' {
      (SELECT * FROM type::record('user', $user)
        WHERE deleted_at = NONE AND login_method != 'form'
          AND crypto::bcrypt::compare(password, $password) = true)[0]
    } ELSE {
      NONE
    };

    IF $found = NONE {
      -- Returning NONE (instead of THROW) keeps this write: a THROW would roll it back.
      CREATE login_failure SET at = time::now(), subject = $subject;
      DELETE login_failure WHERE at < time::now() - 1d;
      RETURN NONE;
    };

    DELETE login_failure WHERE subject = $subject;
    RETURN $found.id;
  }
  DURATION FOR TOKEN 16h, FOR SESSION NONE;
