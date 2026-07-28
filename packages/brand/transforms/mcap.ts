/**
 * `50-mcap-compat`.
 *
 * The recorder writes custom ROS2 message schemas under a brand-shaped
 * namespace - upstream `stera/msg/TrackingState` and friends - and those names
 * are baked into every `.mcap` file already on disk. Renaming the namespace is
 * the correct thing for a fork to do, but it means the app can no longer read
 * its own older recordings: the decoder's switch simply falls through to the
 * fallback case and the data silently degrades.
 *
 * So the rename keeps a legacy alias. Dart lets consecutive `case` labels share
 * one body, which makes the fix a one-line insertion per schema:
 *
 *     case "acme_vision/msg/TrackingState":
 *     case "stera/msg/TrackingState":        // <- added here
 *       return _trackingState(cdr);
 *
 * Opt out with `--break-mcap-compat` (or `compat.keepMcapAliases: false`) when
 * starting a fork with no recordings to preserve.
 */

import { applyTokens } from "../lib/tokens.ts";
import type { Change, Ctx, Transform } from "../lib/types.ts";
import type { Brand } from "../lib/types.ts";

const DECODER_PATH =
  "apps/mobile/lib/src/services/mcap_reader/cdr/ros2_message_decoder.dart";

const LEGACY_MARKER = "brand: legacy schema alias";

export const mcapCompat: Transform = {
  id: "50-mcap-compat",
  title: "Keep decoding pre-rebrand MCAP recordings",
  needs: ["20-rewrite-content"],

  owns(_prev: Brand, _next: Brand): string[] {
    return [DECODER_PATH];
  },

  enabled(ctx: Ctx): boolean {
    return ctx.files.exists(DECODER_PATH);
  },

  async plan(ctx: Ctx): Promise<Change[]> {
    const original = await ctx.files.read(DECODER_PATH);

    // This transform owns the file, so it does the token rewrite the sweep
    // would otherwise have done.
    const renamed = applyTokens(original, ctx.tokens).text;

    const previousNamespace = ctx.prev.identifiers.mcapSchemaNamespace;
    const nextNamespace = ctx.next.identifiers.mcapSchemaNamespace;

    if (!ctx.next.compat.keepMcapAliases || previousNamespace === nextNamespace) {
      return renamed === original
        ? []
        : [{ kind: "write", path: DECODER_PATH, contents: renamed }];
    }

    if (renamed.includes(`"${previousNamespace}/msg/`)) {
      ctx.log.debug("MCAP legacy aliases already present");
      return renamed === original
        ? []
        : [{ kind: "write", path: DECODER_PATH, contents: renamed }];
    }

    const lines = renamed.split("\n");
    const output: string[] = [];
    const casePattern = new RegExp(
      `^(\\s*)case "${nextNamespace.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/msg/([A-Za-z0-9_]+)":\\s*$`
    );
    let added = 0;

    for (const line of lines) {
      output.push(line);
      const match = casePattern.exec(line);
      if (match) {
        const [, indent, schema] = match;
        output.push(
          `${indent}// ${LEGACY_MARKER}: recordings made before the rebrand`,
          `${indent}case "${previousNamespace}/msg/${schema}":`
        );
        added += 1;
      }
    }

    if (added === 0) {
      ctx.log.warn(
        `${DECODER_PATH}: expected to find "${nextNamespace}/msg/*" cases to alias, but found none. ` +
          `Pre-rebrand recordings may not decode - check the file by hand.`
      );
      return renamed === original
        ? []
        : [{ kind: "write", path: DECODER_PATH, contents: renamed }];
    }

    ctx.log.info(
      `  kept ${added} legacy "${previousNamespace}/msg/*" alias(es) so older recordings still decode`
    );

    return [{ kind: "write", path: DECODER_PATH, contents: output.join("\n") }];
  },
};
