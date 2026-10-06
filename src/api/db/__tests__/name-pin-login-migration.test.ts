import { readFileSync } from "fs";
import path from "path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  path.resolve(__dirname, "../../../../migrations/2026_10_06_name_pin_login.surql"),
  "utf8",
);

describe("name + PIN login migration", () => {
  // Guests (the login screen before sign-in) can read this view, so it must
  // never expose PINs, usernames or password hashes.
  it("only exposes names in the login directory", () => {
    const view = migration.match(/DEFINE TABLE OVERWRITE login_directory[\s\S]*?AS SELECT ([^;]*?) FROM user/);
    expect(view?.[1].split(",").map(field => field.trim())).toEqual(["id", "first_name", "last_name"]);
  });

  it("identifies PIN users by record, not by the PIN", () => {
    expect(migration).toMatch(/SELECT \* FROM type::record\('user', \$user\)/);
    expect(migration).not.toMatch(/WHERE login = \$login[^}]*login_method = 'pin'/);
  });

  it("counts failures per user", () => {
    expect(migration).toMatch(/WHERE subject = \$subject AND at > time::now\(\) - 15m/);
  });
});
