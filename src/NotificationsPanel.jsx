import React,{useEffect,useState} from 'react';
import {Bell,CheckCheck,X} from 'lucide-react';
import {supabase} from './lib/supabase';

export default function NotificationsPanel({messId,userId,onClose}){
 const [rows,setRows]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 async function load(){if(!supabase||!userId)return;setLoading(true);const {data,error:e}=await supabase.from('notifications').select('id,title,message,type,reference_id,created_at,read_at').eq('user_id',userId).order('created_at',{ascending:false}).limit(50);if(e)setError(e.message);setRows(data||[]);setLoading(false)}
 useEffect(()=>{load()},[userId]);
 async function mark(id){const {error:e}=await supabase.from('notifications').update({read_at:new Date().toISOString()}).eq('id',id).eq('user_id',userId);if(e)setError(e.message);else setRows(x=>x.map(n=>n.id===id?{...n,read_at:new Date().toISOString()}:n))}
 async function markAll(){const {error:e}=await supabase.from('notifications').update({read_at:new Date().toISOString()}).eq('user_id',userId).is('read_at',null);if(e)setError(e.message);else setRows(x=>x.map(n=>({...n,read_at:n.read_at||new Date().toISOString()})))}
 const unread=rows.filter(x=>!x.read_at).length;
 return <div className="modal-backdrop" onClick={onClose}><div className="modal notifications-modal" onClick={e=>e.stopPropagation()}><button className="modal-close" onClick={onClose}><X size={18}/></button><div className="modal-title"><div><h2><Bell size={20}/> Notifications</h2><p className="muted">{unread} unread notification{unread===1?'':'s'}</p></div>{unread>0&&<button className="outline" onClick={markAll}><CheckCheck size={14}/> Mark all read</button>}</div>{error&&<div className="error-banner">{error}</div>}{loading?<div className="empty-state">Loading notifications…</div>:rows.length===0?<div className="empty-state"><Bell size={24}/><b>No notifications</b><span>Important mess updates will appear here.</span></div>:<div className="notification-list">{rows.map(n=><button className={`notification-row ${n.read_at?'read':''}`} key={n.id} onClick={()=>!n.read_at&&mark(n.id)}><span className={`notification-dot notification-${n.type||'info'}`}/><span className="notification-copy"><b>{n.title}</b><span>{n.message}</span><small>{new Date(n.created_at).toLocaleString('en-BD')}</small></span>{!n.read_at&&<strong>NEW</strong>}</button>)}</div>}</div></div>;
}
