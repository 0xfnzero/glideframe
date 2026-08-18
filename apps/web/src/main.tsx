import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Navigate, Route, Routes, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { Workspace } from "../app/dashboard/workspace";
import { Player } from "../app/watch/[token]/player";
import "../app/globals.css";

const API=import.meta.env.VITE_API_URL??"http://127.0.0.1:4100";
function WatchRoute(){const {token}=useParams();return token?<Player token={token}/>:<Navigate to="/dashboard" replace/>}
function VerifyRoute(){const [params]=useSearchParams();const navigate=useNavigate();const [error,setError]=useState("");useEffect(()=>{const token=params.get("token");if(!token){setError("Missing token.");return;}fetch(`${API}/v1/auth/verify`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({token})}).then(async response=>{if(!response.ok)throw new Error();const data=await response.json();localStorage.setItem("glideframe.token",data.accessToken);navigate("/dashboard",{replace:true})}).catch(()=>setError("This sign-in link is invalid or expired."))},[params,navigate]);return <main className="watch-loading">{error||<span/>}</main>}

createRoot(document.getElementById("root")!).render(
  <StrictMode><BrowserRouter><Routes><Route path="/dashboard" element={<Workspace/>}/><Route path="/watch/:token" element={<WatchRoute/>}/><Route path="/auth/verify" element={<VerifyRoute/>}/><Route path="*" element={<Navigate to="/dashboard" replace/>}/></Routes></BrowserRouter></StrictMode>
);
