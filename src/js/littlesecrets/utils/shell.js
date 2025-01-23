const Bun = globalThis.Bun;
import { mkdir } from "node:fs/promises";
import { rm } from "node:fs/promises";

async function mkdtemp({
  prefix = undefined,
  suffix = undefined,
  path = "/tmp",
  mode = 0o700,
} = {}) {
  let iterations = 0;
  const limit = 100;
  while (iterations < limit) {
    const p = `${path || "/tmp"}/${prefix || ""}${Bun.randomUUIDv7()}${
      suffix || ""
    }`;
    try {
      await mkdir(p, mode);
      return p;
    } catch (err) {
      if (err.code !== "EEXIST") {
        throw err;
      }
      iterations++;
    }
  }
  throw new Error("Unable to create temporary directory");
}

async function rmdir(path) {
  // Optionally remove the directory itself
  await rm(path, {
    recursive: true,
    force: true,
  });
}

async function shell(command, options) {
  // SEE: https://bun.sh/docs/api/spawn
  const proc = Bun.spawn(command, options);
  // TODO: Should check status
  return await new Response(proc.stdout).text();
}
export { mkdtemp, rmdir };
// EOF
