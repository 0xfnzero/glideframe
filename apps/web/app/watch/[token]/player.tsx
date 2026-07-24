"use client";

import { type FormEvent, useEffect, useRef, useState } from "react";
import { EyeOff, Lock, Play, Send } from "lucide-react";
import { Brand } from "../../components/Brand";

const API=import.meta.env.VITE_API_URL??"http://127.0.0.1:4100";
type SharedVideo={id:string;title:string;requiresPassword:boolean;playbackUrl?:string;expiresAt:string|null};

export function Player({token}:{token:string}) {
  const [video,setVideo]=useState<SharedVideo|null>(null); const [password,setPassword]=useState(""); const [error,setError]=useState("");
  const session=useRef(crypto.randomUUID()); const sent=useRef(new Set<string>());
  async function load(shareAccess=""){const response=await fetch(`${API}/v1/shares/public/${token}`,{headers:shareAccess?{authorization:`Bearer ${shareAccess}`}:{}});if(!response.ok){setError("This link is unavailable or has expired.");return;}setVideo(await response.json())}
  useEffect(()=>{void load()},[]);
  async function verify(event:FormEvent){event.preventDefault();const response=await fetch(`${API}/v1/shares/public/${token}/verify`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({password})});if(!response.ok){setError("Incorrect password.");return;}const result=await response.json();setError("");await load(result.accessToken)}
  async function track(event:"play"|"progress"|"complete",progress:number){const key=`${event}:${Math.floor(progress*4)}`;if(sent.current.has(key))return;sent.current.add(key);await fetch(`${API}/v1/analytics/shares/${token}/events`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({event,sessionId:session.current,progress,occurredAt:new Date().toISOString()})})}
  if(error&&!video)return <main className="watch-error"><EyeOff/><h1>{error}</h1></main>;
  if(!video)return <main className="watch-loading"><span/></main>;
  if(video.requiresPassword&&!video.playbackUrl)return <main className="watch-shell"><header><Brand/></header><form className="password-panel" onSubmit={verify}><Lock/><h1>{video.title}</h1><label>Password<input autoFocus type="password" value={password} onChange={e=>setPassword(e.target.value)}/></label>{error&&<p className="error-text">{error}</p>}<button className="primary"><Send/>Continue</button></form></main>;
  return <main className="watch-shell"><header><Brand/><span>Shared securely</span></header><section className="video-stage"><video controls autoPlay src={video.playbackUrl} onPlay={()=>track("play",0)} onTimeUpdate={e=>{const el=e.currentTarget;if(el.duration&&el.currentTime/el.duration>=.25)void track("progress",el.currentTime/el.duration)}} onEnded={()=>track("complete",1)}/></section><footer><div><Play/><h1>{video.title}</h1></div></footer></main>;
}
