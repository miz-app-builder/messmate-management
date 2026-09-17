import React, { useEffect, useState } from 'react';
import App from './App.jsx';
import BazarPanel from './BazarPanel.jsx';
import FinancePanel from './FinancePanel.jsx';
import LedgerPanel from './LedgerPanel.jsx';
import SettlementPanel from './SettlementPanel.jsx';
import ReportsPanel from './ReportsPanel.jsx';
import NotificationsPanel from './NotificationsPanel.jsx';
import { supabase } from './lib/supabase';
import { Bell, BarChart3, CalendarDays, BookOpen, WalletCards, ShoppingBasket } from 'lucide-react';

const tools = [
  ['notifications', Bell, 'Notifications'],
  ['reports', BarChart3, 'Reports'],
  ['settlement', CalendarDays, 'Settlement'],
  ['ledger', BookOpen, 'Ledger'],
  ['finance', WalletCards, 'Finance'],
  ['bazar', ShoppingBasket, 'Bazar'],
];

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
    const { data } = await supabase.from('mess_members').select('id,mess_id,role,status').eq('user_id', userId).eq('status', 'active').order('activated_at', { ascending: false }).limit(1).maybeSingle();
    setMembership(data || null);
    const { count } = await supabase.from('notifications').select('id', { count: 'exact', head: true }).eq('user_id', userId).is('read_at', null);
    setUnread(count || 0);
  }

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session || null);
      if (data.session) load(data.session.user.id);
    });
    const { data: auth } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next || null);
      if (next) load(next.user.id);
      else { setMembership(null); setUnread(0); }
    });
    return () => auth.subscription.unsubscribe();
  }, []);

  const open = (name) => {
    if (name === 'notifications') setShowNotifications(true);
    if (name === 'reports') setShowReports(true);
    if (name === 'settlement') setShowSettlement(true);
    if (name === 'ledger') setShowLedger(true);
    if (name === 'finance') setShowFinance(true);
    if (name === 'bazar') setShowBazar(true);
  };

  return <>
    <App />
    {session && membership && <>
      <section className="workspace-tools" aria-label="Workspace tools">
        <div className="workspace-tools-head">
          <b>Workspace tools</b>
          <span>Finance, reports and operations</span>
        </div>
        <div className="workspace-tools-grid">
          {tools.map(([key, Icon, label]) => (
            <button className="workspace-tool" type="button" key={key} onClick={() => open(key)}>
              <Icon />
              <span>{label}{key === 'notifications' && unread > 0 ? ` (${unread})` : ''}</span>
            </button>
          ))}
        </div>
      </section>
      {showNotifications && <NotificationsPanel messId={membership.mess_id} userId={session.user.id} onClose={() => { setShowNotifications(false); load(session.user.id); }} />}
      {showReports && <ReportsPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role === 'manager'} onClose={() => setShowReports(false)} />}
      {showSettlement && <SettlementPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role === 'manager'} onClose={() => setShowSettlement(false)} />}
      {showLedger && <LedgerPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role === 'manager'} onClose={() => setShowLedger(false)} />}
      {showBazar && <BazarPanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role === 'manager'} onClose={() => setShowBazar(false)} />}
      {showFinance && <FinancePanel messId={membership.mess_id} memberId={membership.id} isManager={membership.role === 'manager'} onClose={() => setShowFinance(false)} />}
    </>}
  </>;
}
