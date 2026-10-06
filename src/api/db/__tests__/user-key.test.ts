import { describe, expect, it } from "vitest";
import { RecordId } from "surrealdb";
import { userKey } from "@/api/db/auth.ts";

describe("userKey", () => {
  it("takes the key from a RecordId", () => {
    expect(userKey(new RecordId("login_directory", "abc123"))).toBe("abc123");
  });

  it("takes the key from a string id", () => {
    expect(userKey("user:abc123")).toBe("abc123");
    expect(userKey("user:⟨odd-key⟩")).toBe("odd-key");
  });
});
