import React, { useEffect, useMemo, useState } from 'react';
import { BarChart3, Download, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money = v => `৳${Number(v || 0).toLocaleString('en-BD',{minimumFractionDigits:2,maximumFractionDigits:2})`;
const iso = d => d.toISOString().slice(0,10);
const today = () => iso(new Date());
const shift = (date, days) => { const d=new Date(`${date}T00:00:00`); d.setDate(d.getDate()+days); return iso(d); };

export default function ReportsPanel({ messId, memberId, isManager=false, onClose }) {
  const [period,setPeriod]=useState('month');
  const [start,setStart]=useState(shift(today(),-29));
  const [end,setEnd]=useState(today());
  const [members,setMembers]=useState([]),[meals,setMeals]=useState([]),[bazar,setBazar]=useState([]),[expenses,setExpenses]=useState([]),[deposits,setDeposits]=useState([]);
  const [loading,setLoading]=useState(true),[error,setError]=useState('');

  useEffect(()=>{
    if(period==='day'){setStart(today());setEnd(today());}
    if(period==='week'){setStart(shift(today(),-6));setEnd(today());}
    if(period==='month'){setStart(shift(today(),-29));setEnd(today());}
  },[period]);

  async function load(){
    if(!supabase||!messId)return;
    setLoading(true);setError('');
    const memberQuery=supabase.from('mess_members').select('id,status,role,profiles(full_name)').eq('mess_id',messId).in('status',['active','left']);
    const mealQuery=supabase.from('meal_entries').select('id,member_id,meal_date,status,meal_type_id').eq('mess_id',messId).gte('meal_date',start).lte('meal_date',end);
    const bazarQuery=supabase.from('bazar_entries').select('id,purchased_on,total_amount,status,buyer_member_id').eq('mess_id',messId).gte('purchased_on',start).lte('purchased_on',end).eq('status','approved');
    const expenseQuery=supabase.from('expenses').select('id,amount,expense_date,status,description').eq('mess_id',messId).gte('expense_date',start).lte('expense_date',end).eq('status','approved');
    const depositQuery=supabase.from('deposits').select('id,member_id,amount,deposited_on,status').eq('mess_id',messId).gte('deposited_on',start).lte('deposited_on',end).eq('status','approved');
    const [m,me,b,e,d]=await Promise.all([memberQuery,mealQuery,bazarQuery,expenseQuery,depositQuery]);
    const bad=[m,me,b,e,d].find(x=>x.error); if(bad){setError(bad.error.message);setLoading(false);return;}
    setMembers(m.data||[]);setMeals(me.data||[]);setBazar(b.data||[]);setExpenses(e.data||[]);setDeposits(d.data||[]);setLoading(false);
  }
  useEffect(()=>{load()},[messId,start,end]);

  const visibleMembers=useMemo(()=>isManager?members:members.filter(m=>m.id===memberId),[members,isManager,memberId]);
  const approvedBazar=bazar.reduce((s,x)=>s+Number(x.total_amount||0),0);
  const expenseTotal=expenses.reduce((s,x)=>s+Number(x.amount||0),0);
  const depositTotal=deposits.filter(x=>isManager||x.member_id===memberId).reduce((s,x)=>s+Number(x.amount||0),0);
  const mealTotal=meals.filter(x=>x.status==='on' && (isManager||x.member_id===memberId)).length;
  const byMember=visibleMembers.map(m=>{const ms=meals.filter(x=>x.member_id===m.id&&x.status==='on').length;const paid=deposits.filter(x=>x.member_id===m.id).reduce((s,x)=>s+Number(x.amount||0),0);return {...m,mealCount:ms,paid};});

  function exportCsv(){
    const rows=[['MessMate Report',`${start} to ${end}`],[],['Member','Meals','Deposits']];
    byMember.forEach(m=>rows.push([m.profiles?.full_name||'Member',m.mealCount,m.paid.toFixed(2)]));
    rows.push([],['Approved Bazar',approvedBazar.toFixed(2)],['Expenses',expenseTotal.toFixed(2)],['Deposits',depositTotal.toFixed(2)]);
    const csv=rows.map(r=>r.map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(',')).join('\n');
    const blob=new Blob([csv],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`messmate-report-${start}-to-${end}.csv`;a.click();URL.revokeObjectURL(url);
  }

  return <div className="modal-backdrop" onClick={onClose}><div className="modal reports-modal" onClick={e=>e.stopPropagation()}>
    <button className="modal-close" onClick={onClose}><X size={18}/></button>
    <div className="modal-title"><div><h2><BarChart3 size={20}/> Reports</h2><p className="muted">Daily, weekly and monthly activity summary.</p></div></div>
    <div className="reports-toolbar"><label>Period<select value={period} onChange={e=>setPeriod(e.target.value)}><option value="day">Today</option><option value="week">Last 7 days</option><option value="month">Last 30 days</option><option value="custom">Custom</option></select></label><label>From<input type="date" value={start} onChange={e=>{setPeriod('custom');setStart(e.target.value)}}/></label><label>To<input type="date" value={end} onChange={e=>{setPeriod('custom');setEnd(e.target.value)}}/></label><button className="outline" onClick={exportCsv} disabled={loading}><Download size={14}/> CSV</button></div>
    {error&&<div className="error-banner">{error}</div>}
    {loading?<div className="empty-state">Loading report…</div>:<>
      <div className="report-cards"><div><span>Meals</span><strong>{mealTotal}</strong></div><div><span>Approved Bazar</span><strong>{money(approvedBazar)}</strong></div><div><span>Expenses</span><strong>{money(expenseTotal)}</strong></div><div><span>Deposits</span><strong>{money(depositTotal)}</strong></div></div>
      <div className="report-section"><h3>Member summary</h3><div className="report-list">{byMember.length?byMember.map(m=><div className="report-row" key={m.id}><div><b>{m.profiles?.full_name||'Member'}</b><span>{m.status}</span></div><strong>{m.mealCount} meals</strong><strong>{money(m.paid)}</strong></div>):<div className="empty-state">No members found.</div>}</div></div>
      {isManager&&<div className="report-section"><h3>Approved bazar</h3><div className="report-list">{bazar.length?bazar.map(x=><div className="report-row" key={x.id}><div><b>{x.purchased_on}</b><span>{x.buyer_member_id}</span></div><strong>{money(x.total_amount)}</strong></div>):<div className="empty-state">No approved bazar entries.</div>}</div></div>}
    </>}
  </div></div>;
}
