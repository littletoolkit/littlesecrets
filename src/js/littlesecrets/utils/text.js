const TEXT_DECODER = new TextDecoder();
function str(value) {
  switch (value?.constructor) {
    case ArrayBuffer:
    case Uint8Array:
      return TEXT_DECODER.decode(value);
    case String:
      return value;
    case undefined:
      return "";
    default:
      return value.toString ? value.toString() : `${value}`;
  }
}

const TEXT_ENCODER = new TextEncoder();
function bytes(value) {
  switch (value?.constructor) {
    case String:
      return TEXT_ENCODER.encode(value);
    // TODO: Should support more cases
    default:
      return value;
  }
}

export { str, bytes };
// EOF
