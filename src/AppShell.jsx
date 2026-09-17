import React, { useEffect, useState } from 'react';
import App from './App.jsx';
import BazarPanel from './BazarPanel.jsx';
import FinancePanel from './FinancePanel.jsx';
import LedgerPanel from './LedgerPanel.jsx';
import SettlementPanel from './SettlementPanel.jsx';
import ReportsPanel from './ReportsPanel.jsx';
import NotificationsPanel from './NotificationsPanel.jsx';
import { supabase } from './lib/supabase';

export default function AppShell() {
  const [session, setSession] = useState(null);
  const [membership, setMembership] = useState(null);
  const [showBazar, setShowBazar] = useState(false);
  const [showFinance, setShowFinance] = useState(false);
  const [showLedger, setShowLedger] = useState(false);
  const [showSettlement, setShowSettlement] = useState(false);
  const [showReports, setShowReports] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [unread, setUnread] = useState(0);

  async function load(userId) {
    if (!supabase || !userId) { setMembership(null); return; }
    const { data } = await supabase.from('mess_members').select('id,mess_id,role,status').eq('user_id', userId).eq('status', 'active').order('activated_at',{ascending:false}).limit(1).maybeSingle();
    setMembership(data || null);
    const { count } = await supabase.from('notifications').select('id',{count:'exact',head:true}).eq('user_id',userId).is('read_at',null);
    setUnread(count || 0);
  }
  useEffect(()=>{
    if(!supabase)return;
    supabase.auth.getSession().then(({data})=>{setSession(data.session||null);if(data.session)load(data.session.user.id)});
    const {data:auth}=supabase.auth.onAuthStateChange((_event,next)=>{setSession(next||null);if(next)load(next.user.id);else{setMembership(null);setUnread(0)}});
    return()=>auth.subscription.unsubscribe();
  },[]);

  return <><App/>{session&&membership&&<>
    <div style={{position:'fixed',right:20,bottom:78,zIndex:40,display:'flex',gap:8,flexWrap:'wrap',justifyContent:'flex-end'}}>
      <button type="button" aria-label="Open Notifications" onClick={()=>setShowNotifications(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',boxShadow:'0 10px 28px rgba(0,0,0,.18)',cursor:'pointer',fontWeight:700}}>🔔 Notifications{unread>0?` (${unread})`:''}</button>
      <button type="button" onClick={()=>setShowReports(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',cursor:'pointer',fontWeight:700}}>📊 Reports</button>
      <button type="button" onClick={()=>setShowSettlement(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',cursor:'pointer',fontWeight:700}}>📅 Settlement</button>
      <button type="button" onClick={()=>setShowLedger(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',cursor:'pointer',fontWeight:700}}>📒 Ledger</button>
      <button type="button" onClick={()=>setShowFinance(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',cursor:'pointer',fontWeight:700}}>💰 Finance</button>
      <button type="button" onClick={()=>setShowBazar(true)} style={{border:0,borderRadius:999,padding:'12px 16px',background:'var(--accent,#111827)',color:'#fff',cursor:'pointer',fontWeight:700}}>🛒 Bazar</button>
    </div>
    {showNotifications&&<NotificationsPanel messId={membership.mess_id} userId={session.user.id} onClose={()=>{setShowNotifications(false);load(session.user.id)}}/>}
    {showReports&&<ReportsPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role==='manager'} onClose={()=>setShowReports(false)}/>} 
    {showSettlement&&<SettlementPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role==='manager'} onClose={()=>setShowSettlement(false)}/>} 
    {showLedger&&<LedgerPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role==='manager'} onClose={()=>setShowLedger(false)}/>} 
    {showBazar&&<BazarPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role==='manager'} onClose={()=>setShowBazar(false)}/>} 
    {showFinance&&<FinancePanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role==='manager'} onClose={()=>setShowFinance(false)}/>} 
  </>}</>;
}
