"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { BarChart3, Check, ChevronDown, CloudUpload, Copy, ExternalLink, FileVideo, Globe2, Lock, LogOut, Plus, RefreshCw, Sparkles } from "lucide-react";
import { Brand } from "../components/Brand";

const API = import.meta.env.VITE_API_URL ?? "http://127.0.0.1:4100";

type Entitlement = {
  plan: "community";
  monthlyAiMinutes: number;
  aiMinutesUsed: number;
  storageBytes: number;
  storageBytesUsed: number;
  monthlyShares: number;
  sharesUsed: number;
};

type Share = {
  id: string;
  token: string;
  title: string;
  url: string;
  protected: boolean;
  expiresAt: string | null;
  revokedAt: string | null;
  createdAt: string;
  analytics: { views: number; uniqueViewers: number; completionRate: number };
};

type Locale = "en" | "zh";

const copy = {
  en: {
    library: "Library",
    shares: "Shared videos",
    usage: "Usage",
    newShare: "Upload video",
    title: "Publish a recording",
    drop: "Drop an MP4 or QuickTime recording",
    choose: "Choose video",
    password: "Password protection",
    expiry: "Link expires",
    publish: "Upload and create link",
    recent: "Recent shares",
    empty: "No shared videos yet",
    views: "views",
    completion: "completion",
    ai: "AI minutes",
    storage: "Community storage",
    links: "Monthly shares",
    signIn: "Sign in",
    email: "Work email",
    send: "Send magic link",
    check: "Check your inbox to finish signing in.",
    dev: "Continue in development",
    logout: "Sign out",
    copied: "Copied",
    edition: "Community Edition"
  },
  zh: {
    library: "项目库",
    shares: "分享视频",
    usage: "用量",
    newShare: "上传视频",
    title: "发布录制",
    drop: "拖入 MP4 或 QuickTime 录制文件",
    choose: "选择视频",
    password: "密码保护",
    expiry: "链接到期",
    publish: "上传并创建链接",
    recent: "最近分享",
    empty: "还没有分享视频",
    views: "次观看",
    completion: "完成率",
    ai: "AI 分钟",
    storage: "社区版存储",
    links: "每月分享",
    signIn: "登录",
    email: "工作邮箱",
    send: "发送登录链接",
    check: "请检查邮箱完成登录。",
    dev: "开发环境继续",
    logout: "退出登录",
    copied: "已复制",
    edition: "社区版"
  }
};

export function Workspace() {
  const [locale, setLocale] = useState<Locale>("en");
  const t = copy[locale];
  const [token, setToken] = useState<string | null>(null);
  const [entitlement, setEntitlement] = useState<Entitlement | null>(null);
  const [shares, setShares] = useState<Share[]>([]);
  const [email, setEmail] = useState("");
  const [previewToken, setPreviewToken] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [password, setPassword] = useState("");
  const [days, setDays] = useState("0");
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setLocale(navigator.language.startsWith("zh") ? "zh" : "en");
    setToken(localStorage.getItem("glideframe.token"));
  }, []);

  const api = useCallback(async (path: string, init: RequestInit = {}) => {
    const response = await fetch(`${API}${path}`, {
      ...init,
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}), ...(init.headers ?? {}) }
    });
    if (!response.ok) throw new Error((await response.json()).error ?? "request_failed");
    return response.status === 204 ? null : response.json();
  }, [token]);

  const refresh = useCallback(async () => {
    if (!token) return;
    try {
      const [nextEntitlement, nextShares] = await Promise.all([api("/v1/entitlements"), api("/v1/shares")]);
      setEntitlement(nextEntitlement);
      setShares(nextShares);
    } catch {
      localStorage.removeItem("glideframe.token");
      setToken(null);
    }
  }, [api, token]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function requestLink() {
    setBusy(true);
    setNotice("");
    try {
      const response = await fetch(`${API}/v1/auth/magic-link`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email })
      });
      const data = await response.json();
      setPreviewToken(data.previewToken ?? null);
      setNotice(t.check);
    } finally {
      setBusy(false);
    }
  }

  async function verifyDev() {
    if (!previewToken) return;
    setBusy(true);
    try {
      const response = await fetch(`${API}/v1/auth/verify`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token: previewToken })
      });
      const data = await response.json();
      localStorage.setItem("glideframe.token", data.accessToken);
      setToken(data.accessToken);
      setPreviewToken(null);
      setNotice("");
    } finally {
      setBusy(false);
    }
  }

  async function publish() {
    if (!file || !token) return;
    setBusy(true);
    setNotice("");
    try {
      const chunk = 8 * 1024 * 1024;
      const partCount = Math.ceil(file.size / chunk);
      const created = await api("/v1/uploads", {
        method: "POST",
        body: JSON.stringify({ filename: file.name, contentType: file.type === "video/quicktime" ? "video/quicktime" : "video/mp4", sizeBytes: file.size, partCount })
      });
      const parts = [];
      for (let index = 0; index < partCount; index += 1) {
        const response = await fetch(created.partUrls[index], {
          method: "PUT",
          headers: { "content-type": "application/octet-stream" },
          body: file.slice(index * chunk, Math.min((index + 1) * chunk, file.size))
        });
        if (!response.ok) throw new Error("upload_failed");
        parts.push({ partNumber: index + 1, etag: response.headers.get("etag") ?? `part-${index + 1}` });
      }
      await api(`/v1/uploads/${created.id}/complete`, { method: "POST", body: JSON.stringify({ parts }) });
      const expiresAt = days === "0" ? undefined : new Date(Date.now() + Number(days) * 86_400_000).toISOString();
      const share = await api("/v1/shares", {
        method: "POST",
        body: JSON.stringify({ uploadId: created.id, title: title || file.name.replace(/\.[^.]+$/, ""), ...(password ? { password } : {}), ...(expiresAt ? { expiresAt } : {}) })
      });
      await navigator.clipboard.writeText(share.url);
      setNotice(`${t.copied}: ${share.url}`);
      setFile(null);
      setTitle("");
      setPassword("");
      await refresh();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "upload_failed");
    } finally {
      setBusy(false);
    }
  }

  if (!token) {
    return (
      <main className="auth-shell">
        <section className="auth-panel">
          <Brand />
          <div><h1>{t.signIn}</h1><p>GlideFrame Community</p></div>
          <label>{t.email}<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@company.com" /></label>
          <button className="primary" disabled={busy || !email.includes("@")} onClick={requestLink}>{t.send}</button>
          {notice && <p className="notice">{notice}</p>}
          {previewToken && <button className="secondary" onClick={verifyDev}>{t.dev}</button>}
          <button className="locale" onClick={() => setLocale(locale === "en" ? "zh" : "en")}><Globe2 size={15} />{locale === "en" ? "简体中文" : "English"}</button>
        </section>
      </main>
    );
  }

  return (
    <div className="app-shell">
      <aside>
        <Brand />
        <nav><a className="active"><FileVideo />{t.library}</a><a><ExternalLink />{t.shares}</a><a><BarChart3 />{t.usage}</a></nav>
        <div className="plan"><span>COMMUNITY</span><strong>{t.edition}</strong></div>
        <button className="account" onClick={() => { localStorage.removeItem("glideframe.token"); setToken(null); }}><LogOut />{t.logout}</button>
      </aside>
      <main className="workspace">
        <header>
          <div><h1>{t.library}</h1><p>{shares.length} {t.shares.toLowerCase()}</p></div>
          <div className="header-actions"><button className="icon" title="Refresh" onClick={refresh}><RefreshCw /></button><button className="locale" onClick={() => setLocale(locale === "en" ? "zh" : "en")}><Globe2 />{locale === "en" ? "中" : "EN"}</button></div>
        </header>
        <section className="publisher">
          <div className="section-title"><div><h2>{t.title}</h2><p>{file?.name ?? t.drop}</p></div><button className="secondary" onClick={() => input.current?.click()}><Plus />{t.newShare}</button></div>
          <input ref={input} hidden type="file" accept="video/mp4,video/quicktime" onChange={(event) => { const next = event.target.files?.[0] ?? null; setFile(next); setTitle(next?.name.replace(/\.[^.]+$/, "") ?? ""); }} />
          <div className={`dropzone ${file ? "has-file" : ""}`} onClick={() => input.current?.click()}>
            {file ? <><FileVideo /><div><strong>{file.name}</strong><span>{formatBytes(file.size)}</span></div><Check className="check" /></> : <><CloudUpload /><span>{t.choose}</span></>}
          </div>
          {file && <div className="publish-settings"><label>Title<input value={title} onChange={(event) => setTitle(event.target.value)} /></label><label><span><Lock /> {t.password}</span><input type="password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Optional, min. 8 characters" /></label><label>{t.expiry}<span className="select"><select value={days} onChange={(event) => setDays(event.target.value)}><option value="0">Never</option><option value="7">7 days</option><option value="30">30 days</option></select><ChevronDown /></span></label><button className="primary publish" disabled={busy || Boolean(password && password.length < 8)} onClick={publish}>{busy ? <RefreshCw className="spin" /> : <CloudUpload />}{t.publish}</button></div>}
          {notice && <p className="notice wide">{notice}</p>}
        </section>
        <section className="usage-strip">
          <Usage icon={<Sparkles />} label={t.ai} value={entitlement ? `${entitlement.aiMinutesUsed} / ${entitlement.monthlyAiMinutes}` : "-"} />
          <Usage icon={<CloudUpload />} label={t.storage} value={entitlement ? `${formatBytes(entitlement.storageBytesUsed)} / ${formatBytes(entitlement.storageBytes)}` : "-"} />
          <Usage icon={<ExternalLink />} label={t.links} value={entitlement ? `${entitlement.sharesUsed} / ${entitlement.monthlyShares}` : "-"} />
        </section>
        <section className="recent">
          <div className="section-title"><h2>{t.recent}</h2></div>
          {shares.length === 0 ? <div className="empty-row"><FileVideo /><span>{t.empty}</span></div> : <div className="share-list">{shares.map((share) => <article key={share.id}><div className="thumb"><FileVideo /></div><div className="share-main"><strong>{share.title}</strong><span>{new Date(share.createdAt).toLocaleDateString(locale === "zh" ? "zh-CN" : "en-US")}{share.protected && <><i>·</i><Lock size={12} /></>}</span></div><div className="metric"><strong>{share.analytics.views}</strong><span>{t.views}</span></div><div className="metric"><strong>{Math.round(share.analytics.completionRate * 100)}%</strong><span>{t.completion}</span></div><button className="icon" title="Copy link" onClick={() => navigator.clipboard.writeText(share.url)}><Copy /></button><a className="icon" href={share.url} target="_blank" title="Open"><ExternalLink /></a></article>)}</div>}
        </section>
      </main>
    </div>
  );
}

function Usage({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return <div className="usage-item"><span>{icon}</span><div><small>{label}</small><strong>{value}</strong></div></div>;
}

function formatBytes(bytes: number) {
  if (bytes < 1024 ** 2) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
}
