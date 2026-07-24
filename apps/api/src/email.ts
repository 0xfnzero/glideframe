import type { AppConfig } from "./config.js";

export interface MagicLinkMailer { send(email: string, url: string): Promise<void> }

class DevelopmentMailer implements MagicLinkMailer {
  constructor(private readonly log: (fields: object, message: string) => void) {}
  async send(email: string, url: string): Promise<void> { this.log({ email, magicLink: url }, "Magic link created"); }
}

class ResendMailer implements MagicLinkMailer {
  constructor(private readonly apiKey: string, private readonly from: string) {}
  async send(email: string, url: string): Promise<void> {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${this.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({
        from: this.from,
        to: [email],
        subject: "Sign in to GlideFrame",
        html: `<p>Use this secure link to sign in to GlideFrame. It expires in 15 minutes.</p><p><a href="${escapeAttribute(url)}">Sign in to GlideFrame</a></p>`
      })
    });
    if (!response.ok) throw Object.assign(new Error("email_delivery_failed"), { statusCode: 503 });
  }
}

class UnconfiguredMailer implements MagicLinkMailer {
  async send(): Promise<void> { throw Object.assign(new Error("email_not_configured"), { statusCode: 503 }); }
}

export function createMailer(config: AppConfig, log: (fields: object, message: string) => void): MagicLinkMailer {
  if (config.RESEND_API_KEY && config.EMAIL_FROM) return new ResendMailer(config.RESEND_API_KEY, config.EMAIL_FROM);
  return config.NODE_ENV === "production" ? new UnconfiguredMailer() : new DevelopmentMailer(log);
}

function escapeAttribute(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}
