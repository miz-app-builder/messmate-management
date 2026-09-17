import React, { useEffect, useState } from 'react';
import { CalendarCheck, CheckCircle2, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money=v=>`৳${Number(v||0).toLocaleString('en-BD',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
const currentMonth=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-01`};

export default function SettlementPanel({messId,memberId,isManager=false,onClose}){
 const [month,setMonth]=useState(currentMonth()),[members,setMembers]=useState([]),[rows,setRows]=useState([]),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const end=()=>{const d=new Date(`${month}T00:00:00`);return new Date(d.getFullYear(),d.getMonth()+1,0).toISOString().slice(0,10)};
 async function load(){
  if(!supabase||!messId)return; setError('');
  const {data:m,error:me}=await supabase.from('mess_members').select('id,role,status,profiles(full_name)').eq('mess_id',messId).in('status',['active','left']).order('status').order('activated_at');
  if(me){setError(me.message);return} setMembers(m||[]);
  const target=isManager?(m||[]).map(x=>x.id):(memberId?[memberId]:[]);
  const result=await Promise.all(target.map(id=>supabase.rpc('get_monthly_settlement',{p_mess_member_id:id,p_month_start:month})));
  const missing=result.filter(x=>x.error&&String(x.error.message||'').includes('Settlement not found'));
  const other=result.find(x=>x.error&&!String(x.error.message||'').includes('Settlement not found'));
  if(other){setError(other.error.message);return}
  setRows(result.filter(x=>!x.error).map(x=>x.data));
  if(missing.length&&isManager)setMessage(`${missing.length} member(s) are not settled yet.`);
 }
 useEffect(()=>{load()},[messId,memberId,isManager,month]);
 const name=id=>members.find(m=>m.id===id)?.profiles?.full_name||'Member';
 async function closeAll(){
  if(!window.confirm(`Close ${month.slice(0,7)} for all active/left members? This creates final monthly snapshots.`))return;
  setBusy(true);setError('');setMessage('');const {data,error:e}=await supabase.rpc('close_month_for_mess',{p_mess_id:messId,p_month_start:month});setBusy(false);if(e)setError(e.message);else{setMessage(`${data||0} member settlement(s) closed.`);load()}}
 async function closeOne(id){
  setBusy(true);setError('');const {error:e}=await supabase.rpc('create_monthly_settlement',{p_mess_id:messId,p_member_id:id,p_month_start:month});setBusy(false);if(e)setError(e.message);else{setMessage('Settlement closed.');load()}}
 return <div className="modal-backdrop" onClick={onClose}><div className="modal settlement-modal" onClick={e=>e.stopPropagation()}>
  <button className="modal-close" onClick={onClose}><X size={18}/></button>
  <div className="modal-title"><div><h2><CalendarCheck size={20}/> Monthly Settlement</h2><p className="muted">Close the monthly accounting snapshot after reviewing meals, bazar and payments.</p></div></div>
  <div className="settlement-toolbar"><label>Month<input type="month" value={month.slice(0,7)} onChange={e=>setMonth(`${e.target.value}-01`)}/></label>{isManager&&<button className="primary" disabled={busy} onClick={closeAll}>{busy?'Closing…':'Close month for all'}</button>}</div>
  {error&&<div className="error-banner">{error}</div>}{message&&<div className="notice">{message}</div>}
  <div className="settlement-list">{rows.length===0?<div className="empty-state"><CalendarCheck size={24}/><b>No closed settlement</b><span>{isManager?'Review the month and use “Close month for all”.':'Your manager has not closed this month yet.'}</span></div>:rows.map(r=><div className="settlement-card" key={r.id}><div><b>{name(r.member_id)}</b><span>{r.month_start} → {r.month_end} · {Number(r.total_meals||0)} meals</span></div><div className="settlement-values"><span>Meal {money(r.meal_cost)}</span><span>Other {money(r.other_cost)}</span><span>Paid {money(r.total_paid)}</span><strong className={`balance-${Number(r.balance)>0?'due':Number(r.balance)<0?'advance':'settled'}`}>{Number(r.balance)>0?'Due':Number(r.balance)<0?'Advance':'Settled'} {money(Math.abs(Number(r.balance||0)))}</strong></div><span className="settlement-closed"><CheckCircle2 size={14}/> Closed</span></div>)}</div>
  <div className="security-note">A settlement is a financial snapshot. Use an audited ledger adjustment for later corrections rather than silently changing the closed record.</div>
 </div></div>
}
