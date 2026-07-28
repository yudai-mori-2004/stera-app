/** Thin wrappers over the git commands the engine needs. */

export interface GitResult {
  code: number;
  stdout: string;
  stderr: string;
}

export const git = async (
  root: string,
  args: readonly string[]
): Promise<GitResult> => {
  const proc = Bun.spawn(["git", ...args], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { code, stdout, stderr };
};

export const gitOrThrow = async (
  root: string,
  args: readonly string[]
): Promise<string> => {
  const result = await git(root, args);
  if (result.code !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${result.stderr.trim()}`);
  }
  return result.stdout;
};

export const isGitRepo = async (root: string): Promise<boolean> => {
  const result = await git(root, ["rev-parse", "--git-dir"]);
  return result.code === 0;
};

export const headSha = async (root: string): Promise<string> => {
  const result = await git(root, ["rev-parse", "HEAD"]);
  return result.code === 0 ? result.stdout.trim() : "";
};

/** Porcelain status lines; empty means a clean tree. */
export const dirtyFiles = async (root: string): Promise<string[]> => {
  const out = await gitOrThrow(root, ["status", "--porcelain"]);
  return out.split("\n").filter((line) => line.trim().length > 0);
};

export const diffStat = async (root: string): Promise<string> => {
  const result = await git(root, ["diff", "--stat"]);
  return result.stdout;
};
