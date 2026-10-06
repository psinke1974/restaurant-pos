import { readFileSync } from "fs";
import path from "path";
import { describe, expect, it } from "vitest";
import { Tables } from "@/api/db/tables.ts";

const migration = readFileSync(
  path.resolve(__dirname, "../../../../migrations/2026_10_06_record_access.surql"),
  "utf8",
);

const tablesWithPermissions = new Set(
  [...migration.matchAll(/^ALTER TABLE ([a-z_0-9]+) PERMISSIONS/gm)].map(match => match[1]),
);

describe("record access migration", () => {
  // Staff sign in as record users, who see nothing on a table without explicit
  // permissions. A table missing here silently returns no rows in the app.
  it("grants permissions on every table the app uses", () => {
    const missing = Object.values(Tables).filter(table => !tablesWithPermissions.has(table));
    expect(missing).toEqual([]);
  });

  it("never lets staff delete orders", () => {
    expect(migration).toMatch(/ALTER TABLE order PERMISSIONS[\s\S]*?FOR delete NONE;/);
  });

  it("hides password hashes from everyone", () => {
    expect(migration).toMatch(/DEFINE FIELD OVERWRITE password ON user[^;]*FOR select NONE/);
  });
});
