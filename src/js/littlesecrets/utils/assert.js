function assertType(value, type) {
  if (!(value instanceof type)) {
    throw new Error(
      `[assertType] value not of expected type: ${value?.constructor?.name} != ${type?.name}`
    );
  }
}

async function assertExists(path) {
  if (!(await Bun.exists(path))) {
    throw new Error(`[assertExists] path does not exists: ${path}`);
  }
}

export { assertType, assertExists };
// EOF
