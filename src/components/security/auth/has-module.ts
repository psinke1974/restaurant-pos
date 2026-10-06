import { SecurityManager } from "@/providers/security.provider";

/** Whether the approving user's role grants `module` (same rule as before: role modules only). */
export const hasModule = (manager: SecurityManager, module?: string): boolean => {
  if (!manager || !module) {
    return false;
  }
  const role = manager.user_role as { roles?: string[] } | undefined;
  return Array.isArray(role?.roles) && role.roles.includes(module);
};
