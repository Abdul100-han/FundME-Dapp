type SuccessfulRead<T> = {
  status: "success";
  result: T;
};

export function unwrapReadContractResult<T>(
  value: unknown,
): T | undefined {
  if (
    typeof value === "object" &&
    value !== null &&
    "status" in value &&
    (value as { status: string }).status === "success" &&
    "result" in value
  ) {
    return (value as SuccessfulRead<T>).result;
  }

  return undefined;
}
