import React, { useEffect, useState } from 'react';
import App from './App.jsx';
import BazarPanel from './BazarPanel.jsx';
import { supabase } from './lib/supabase';

export default function AppShell() {
  const [session, setSession] = useState(null);
  const [membership, setMembership] = useState(null);
  const [showBazar, setShowBazar] = useState(false);

  async function load(userId) {
    if (!supabase || !userId) { setMembership(null); return; }
    const { data } = await supabase
      .from('mess_members')
      .select('id,mess_id,role,status')
      .eq('user_id', userId)
      .eq('status', 'active')
      .order('activated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    setMembership(data || null);
  }

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session || null);
      if (data.session) load(data.session.user.id);
    });
    const { data: auth } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next || null);
      if (next) load(next.user.id); else setMembership(null);
    });
    return () => auth.subscription.unsubscribe();
  }, []);

  return <>
    <App />
    {session && membership && <>
      <button
        type="button"
        aria-label="Open Bazar"
        onClick={() => setShowBazar(true)}
        style={{
          position: 'fixed', right: 20, bottom: 78, zIndex: 40,
          display: 'inline-flex', alignItems: 'center', gap: 8,
          border: 0, borderRadius: 999, padding: '12px 16px',
          background: 'var(--accent, #111827)', color: '#fff',
          boxShadow: '0 10px 28px rgba(0,0,0,.18)', cursor: 'pointer', fontWeight: 700
        }}
      >🛒 Bazar</button>
      {showBazar && <BazarPanel
        messId={membership.mess_id}
        memberId={membership.id}
        isManager={membership.role === 'manager'}
        onClose={() => setShowBazar(false)}
      />}
    </>}
  </>;
}
