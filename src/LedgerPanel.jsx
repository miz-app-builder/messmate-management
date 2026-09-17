import React, { useEffect, useMemo, useState } from 'react';
import { Calculator, RefreshCw, Wallet, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money=v=>`৳${Number(v||0).toLocaleString('en-BD',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
const monthStart=()=>{const d=new Date();return new Date(d.getFullYear(),d.getMonth(),1).toISOString().slice(0,10)};
const monthEnd=()=>{const d=new Date();return new Date(d.getFullYear(),d.getMonth()+1,0).toISOString().slice(0,10)};

export default function LedgerPanel({messId,memberId,isManager=false,onClose}){
 const [start,setStart]=useState(monthStart()),[end,setEnd]=useState(monthEnd());
 const [rate,setRate]=useState(null),[rows,setRows]=useState([]),[members,setMembers]=useState([]);
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const [selected,setSelected]=useState(memberId||'');
 async function load(){
  if(!supabase||!messId)return; setError('');
  const {data:r,error:re}=await supabase.rpc('calculate_meal_rate',{p_mess_id:messId,p_period_start:start,p_period_end:end});
  if(re){setError(re.message);return} setRate(r);
  const {data:mm,error:me}=await supabase.from('mess_members').select('id,role,status,profiles(full_name)').eq('mess_id',messId).in('status',['active','left']).order('status').order('activated_at');
  if(me){setError(me.message);return} setMembers(mm||[]);
  const target=isManager?(mm||[]).map(x=>x.id):(memberId?[memberId]:[]);
  const results=await Promise.all(target.map(id=>supabase.rpc('get_member_balance',{p_mess_member_id:id,p_period_start:start,p_period_end:end})));
  const bad=results.find(x=>x.error); if(bad){setError(bad.error.message);return}
  setRows(results.flatMap(x=>x.data||[]));
 }
 useEffect(()=>{load()},[messId,memberId,isManager,start,end]);
 const visible=useMemo(()=>isManager?rows:rows.filter(x=>x.member_id===memberId),[rows,isManager,memberId]);
 const name=id=>members.find(m=>m.id===id)?.profiles?.full_name||'Member';
 async function rebuild(){setBusy(true);setError('');setMessage('');const {data,error:e}=await supabase.rpc('rebuild_period_ledger',{p_mess_id:messId,p_period_start:start,p_period_end:end});setBusy(false);if(e)setError(e.message);else{setMessage(`Ledger rebuilt for ${data||0} member(s).`);load()}}
 return <div className="modal-backdrop" onClick={onClose}><div className="modal ledger-modal" onClick={e=>e.stopPropagation()}>
  <button className="modal-close" onClick={onClose}><X size={18}/></button>
  <div className="modal-title"><div><h2><Wallet size={20}/> Ledger & Balance</h2><p className="muted">Meal rate, member cost and payment balance.</p></div></div>
  <div className="ledger-period"><label>From<input type="date" value={start} onChange={e=>setStart(e.target.value)}/></label><label>To<input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label>{isManager&&<button className="outline" disabled={busy} onClick={rebuild}><RefreshCw size={15}/> {busy?'Rebuilding…':'Rebuild ledger'}</button>}</div>
  {error&&<div className="error-banner">{error}</div>}{message&&<div className="notice">{message}</div>}
  {rate&&<div className="ledger-rate"><div><span>Food cost</span><strong>{money(rate.food_cost)}</strong></div><div><span>Total meals</span><strong>{Number(rate.total_meals||0)}</strong></div><div><span>Meal rate</span><strong>{money(rate.rate)}</strong><small>per meal</small></div></div>}
  {isManager&&<div className="ledger-filter"><label>Member<select value={selected} onChange={e=>setSelected(e.target.value)}><option value="">All active/left members</option>{members.map(m=><option key={m.id} value={m.id}>{name(m.id)}</option>)}</select></label></div>}
  <div className="ledger-list">{visible.filter(r=>!selected||r.member_id===selected).length===0?<div className="empty-state"><Calculator size={24}/><b>No balance data</b><span>Calculate the meal rate after recording meals and approved bazar purchases.</span></div>:visible.filter(r=>!selected||r.member_id===selected).map(r=><div className="ledger-card" key={r.member_id}><div className="ledger-person"><b>{name(r.member_id)}</b><span>{Number(r.total_meals||0)} meals · Paid {money(r.total_paid)}</span></div><div className="ledger-numbers"><span>Meal cost <b>{money(r.meal_cost)}</b></span><span>Other <b>{money(r.other_cost)}</b></span><span>Total <b>{money(r.total_debit)}</b></span><strong className={`balance-${r.balance_status}`}>{r.balance_status==='due'?'Due':r.balance_status==='advance'?'Advance':'Settled'} {money(Math.abs(Number(r.balance||0)))}</strong></div></div>)}</div>
  <div className="security-note">Only approved Bazar purchases are included in the food-cost calculation. Pending/rejected purchases do not affect the meal rate.</div>
 </div></div>
}
