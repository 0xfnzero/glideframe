import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { jwtVerify, SignJWT } from "jose";

const scrypt = promisify(scryptCallback);

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString("hex");
  const digest = (await scrypt(password, salt, 64)) as Buffer;
  return `scrypt:${salt}:${digest.toString("hex")}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algorithm, salt, expectedHex] = stored.split(":");
  if (algorithm !== "scrypt" || !salt || !expectedHex) return false;
  const expected = Buffer.from(expectedHex, "hex");
  const actual = (await scrypt(password, salt, expected.byteLength)) as Buffer;
  return actual.byteLength === expected.byteLength && timingSafeEqual(actual, expected);
}

export async function createAccessToken(secret: string, userId: string, email: string): Promise<string> {
  return new SignJWT({ email, type: "access" })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime("15m")
    .sign(new TextEncoder().encode(secret));
}

export async function createShareToken(secret: string, shareId: string): Promise<string> {
  return new SignJWT({ type: "share", shareId })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(new TextEncoder().encode(secret));
}

export async function verifyToken(secret: string, token: string): Promise<Record<string, unknown>> {
  const result = await jwtVerify(token, new TextEncoder().encode(secret), { algorithms: ["HS256"] });
  return { ...result.payload, sub: result.payload.sub };
}
