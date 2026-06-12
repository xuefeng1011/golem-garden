// Shared command metadata for the Forge view.
// Category keys map to i18n `forge.categories.*`; descriptions to `forge.descriptions.*`.

export interface CommandArgSchema {
  /** Names of required positional args, in order (shown as placeholders). */
  required: string[]
  /** When false, the command takes no args — hide the args input entirely. */
  allowsArgs: boolean
}

export const CATEGORIES: Record<string, string[]> = {
  status: ['status', 'souls', 'rank', 'dashboard', 'overview', 'ov'],
  build: ['build', 'quick', 'assign'],
  review: ['review', 'sync'],
  ops: ['session', 'mailbox', 'worktree', 'recover'],
  analysis: ['insights', 'memory', 'retro', 'chemistry', 'achievement', 'skill-tree', 'dna', 'budget', 'tool-char'],
  manage: ['soul-create', 'pack', 'skill-export', 'skill-import', 'log-add'],
}

const NO_ARGS: CommandArgSchema = { required: [], allowsArgs: false }
const OPTIONAL_ARGS: CommandArgSchema = { required: [], allowsArgs: true }

const ARG_SCHEMAS: Record<string, CommandArgSchema> = {
  // No arguments
  status: NO_ARGS,
  souls: NO_ARGS,
  rank: NO_ARGS,
  dashboard: NO_ARGS,
  overview: NO_ARGS,
  ov: NO_ARGS,
  sync: NO_ARGS,
  // Required arguments
  build: { required: ['task'], allowsArgs: true },
  quick: { required: ['task'], allowsArgs: true },
  assign: { required: ['soul', 'task'], allowsArgs: true },
  review: { required: ['soul'], allowsArgs: true },
  recover: { required: ['soul'], allowsArgs: true },
  'skill-import': { required: ['dir'], allowsArgs: true },
  'log-add': { required: ['soul', 'task', 'result'], allowsArgs: true },
  // Optional arguments (subcommands / flags)
  session: OPTIONAL_ARGS,
  mailbox: OPTIONAL_ARGS,
  worktree: OPTIONAL_ARGS,
  insights: OPTIONAL_ARGS,
  memory: OPTIONAL_ARGS,
  retro: OPTIONAL_ARGS,
  chemistry: OPTIONAL_ARGS,
  achievement: OPTIONAL_ARGS,
  'skill-tree': OPTIONAL_ARGS,
  dna: OPTIONAL_ARGS,
  budget: OPTIONAL_ARGS,
  'tool-char': OPTIONAL_ARGS,
  'soul-create': OPTIONAL_ARGS,
  pack: OPTIONAL_ARGS,
  'skill-export': OPTIONAL_ARGS,
}

export function getArgSchema(command: string): CommandArgSchema {
  return ARG_SCHEMAS[command] ?? OPTIONAL_ARGS
}
