import React, { useEffect, useMemo, useState } from 'react';
import { Check, Clock3, Plus, Receipt, ShoppingBasket, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money = (v) => `৳${Number(v || 0).toLocaleString('en-BD', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const today = () => new Date().toISOString().slice(0, 10);

function StatusBadge({ status }) {
  const label = status === 'approved' ? 'Approved' : status === 'rejected' ? 'Rejected' : 'Pending';
  return <span className={`bazar-status bazar-status-${status}`}>
    {status === 'approved' ? <Check size={13} /> : status === 'rejected' ? <X size={13} /> : <Clock3 size={13} />}
    {label}
  </span>;
}

export default function BazarPanel({ messId, memberId, isManager = false, onClose }) {
  const [entries, setEntries] = useState([]);
  const [permission, setPermission] = useState({ add: false, approve: false });
  const [approvalRequired, setApprovalRequired] = useState(true);
  const [form, setForm] = useState({ purchased_on: today(), total_amount: '', note: '', receipt_url: '' });
  const [editing, setEditing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const load = async () => {
    if (!supabase || !messId) return;
    setError('');
    const [{ data: e, error: ee }, { data: s, error: se }] = await Promise.all([
      supabase.from('bazar_entries')
        .select('id,buyer_member_id,purchased_on,total_amount,status,note,receipt_url,approved_at,approved_by,created_at,updated_at')
        .eq('mess_id', messId)
        .order('purchased_on', { ascending: false })
        .order('created_at', { ascending: false }),
      supabase.from('mess_settings').select('bazar_approval_required').eq('mess_id', messId).maybeSingle(),
    ]);
    if (ee || se) setError((ee || se).message);
    setEntries(e || []);
    setApprovalRequired(s?.bazar_approval_required ?? true);

    if (memberId) {
      const { data: mp } = await supabase.from('member_permissions')
        .select('can_add_bazar,can_approve_bazar')
        .eq('mess_member_id', memberId)
        .maybeSingle();
      setPermission({ add: Boolean(mp?.can_add_bazar), approve: Boolean(mp?.can_approve_bazar) });
    }
  };

  useEffect(() => { load(); }, [messId, memberId]);

  const canAdd = permission.add;
  const canApprove = permission.approve || isManager;
  const pendingCount = useMemo(() => entries.filter((x) => x.status === 'pending').length, [entries]);
  const approvedTotal = useMemo(() => entries.filter((x) => x.status === 'approved').reduce((s, x) => s + Number(x.total_amount || 0), 0), [entries]);

  async function submit(e) {
    e.preventDefault();
    if (!supabase) return;
    setBusy(true); setError(''); setMessage('');
    const amount = Number(form.total_amount);
    if (!Number.isFinite(amount) || amount < 0) {
      setBusy(false); setError('Enter a valid non-negative amount.'); return;
    }
    let result;
    if (editing) {
      result = await supabase.rpc('update_bazar_entry', {
        p_entry_id: editing.id,
        p_purchased_on: form.purchased_on,
        p_total_amount: amount,
        p_note: form.note || null,
        p_receipt_url: form.receipt_url || null,
      });
    } else {
      result = await supabase.rpc('create_bazar_entry', {
        p_mess_id: messId,
        p_purchased_on: form.purchased_on,
        p_total_amount: amount,
        p_note: form.note || null,
        p_receipt_url: form.receipt_url || null,
      });
    }
    setBusy(false);
    if (result.error) { setError(result.error.message); return; }
    setMessage(editing ? 'Bazar entry updated.' : 'Bazar entry added.');
    setEditing(null);
    setForm({ purchased_on: today(), total_amount: '', note: '', receipt_url: '' });
    await load();
  }

  async function review(entry, decision) {
    const reason = window.prompt(decision === 'approved' ? 'Approval note (optional)' : 'Rejection reason (optional)', '') ?? '';
    setBusy(true); setError(''); setMessage('');
    const { error: e } = await supabase.rpc('review_bazar_entry', {
      p_entry_id: entry.id,
      p_decision: decision,
      p_reason: reason || null,
    });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setMessage(`Entry ${decision}.`);
    await load();
  }

  async function toggleApproval() {
    setBusy(true); setError(''); setMessage('');
    const { error: e } = await supabase.rpc('set_bazar_approval_required', { p_mess_id: messId, p_enabled: !approvalRequired });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setApprovalRequired(!approvalRequired);
    setMessage(`Bazar approval ${!approvalRequired ? 'enabled' : 'disabled'}.`);
  }

  function startEdit(entry) {
    setEditing(entry);
    setForm({
      purchased_on: entry.purchased_on || today(),
      total_amount: String(entry.total_amount ?? ''),
      note: entry.note || '',
      receipt_url: entry.receipt_url || '',
    });
    setMessage(''); setError('');
  }

  return <div className="modal-backdrop" onClick={onClose}>
    <div className="modal bazar-modal" onClick={(e) => e.stopPropagation()}>
      <button className="modal-close" onClick={onClose}><X size={18} /></button>
      <div className="modal-title">
        <div><h2><ShoppingBasket size={20} /> Bazar</h2><p className="muted">Record shared grocery and market purchases.</p></div>
        <span className="count-badge">{pendingCount} pending</span>
      </div>

      <div className="bazar-summary">
        <div><span>Approved spend</span><strong>{money(approvedTotal)}</strong></div>
        <div><span>Approval</span><strong>{approvalRequired ? 'Required' : 'Auto-approve'}</strong></div>
      </div>

      {canAdd && <form className="bazar-form" onSubmit={submit}>
        <div className="form-heading"><b>{editing ? 'Edit bazar entry' : 'Add bazar entry'}</b>{editing && <button type="button" className="text-button" onClick={() => { setEditing(null); setForm({ purchased_on: today(), total_amount: '', note: '', receipt_url: '' }); }}>Cancel</button>}</div>
        <div className="form-grid">
          <label>Purchase date<input type="date" value={form.purchased_on} onChange={(e) => setForm({ ...form, purchased_on: e.target.value })} required /></label>
          <label>Total amount<input type="number" min="0" step="0.01" inputMode="decimal" value={form.total_amount} onChange={(e) => setForm({ ...form, total_amount: e.target.value })} placeholder="0.00" required /></label>
          <label className="wide-field">Note <span className="optional">Optional</span><input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="e.g. Vegetables + rice" /></label>
          <label className="wide-field">Receipt URL <span className="optional">Optional</span><input type="url" value={form.receipt_url} onChange={(e) => setForm({ ...form, receipt_url: e.target.value })} placeholder="https://…" /></label>
        </div>
        <button className="primary" disabled={busy}>{busy ? 'Saving…' : editing ? 'Save changes' : <><Plus size={16} /> Add bazar</>}</button>
      </form>}

      {!canAdd && <div className="notice"><Receipt size={14} /> You do not currently have permission to add bazar entries. Ask the manager to enable <b>can_add_bazar</b>.</div>}
      {error && <div className="error-banner">{error}</div>}
      {message && <div className="notice">{message}</div>}

      {isManager && <div className="bazar-admin-row">
        <div><b>Approval required</b><span>{approvalRequired ? 'New entries wait for approval.' : 'New entries are automatically approved.'}</span></div>
        <button className="outline" disabled={busy} onClick={toggleApproval}>{approvalRequired ? 'Turn off' : 'Turn on'}</button>
      </div>}

      <div className="bazar-list">
        {entries.length === 0 ? <div className="empty-state"><ShoppingBasket size={24} /><b>No bazar entries</b><span>Approved purchases will appear here.</span></div> : entries.map((entry) => {
          const mine = entry.buyer_member_id === memberId;
          const canEdit = mine && entry.status !== 'approved' && canAdd;
          return <div className="bazar-entry" key={entry.id}>
            <div className="bazar-entry-main">
              <div><b>{money(entry.total_amount)}</b><span>{entry.purchased_on} · {entry.note || 'No note'}</span></div>
              <StatusBadge status={entry.status} />
            </div>
            <div className="bazar-entry-actions">
              {entry.receipt_url && <a href={entry.receipt_url} target="_blank" rel="noreferrer">Receipt</a>}
              {canEdit && <button className="outline" disabled={busy} onClick={() => startEdit(entry)}>Edit</button>}
              {canApprove && entry.status === 'pending' && <><button className="reject" disabled={busy} onClick={() => review(entry, 'rejected')}>Reject</button><button className="approve" disabled={busy} onClick={() => review(entry, 'approved')}><Check size={14} /> Approve</button></>}
            </div>
          </div>;
        })}
      </div>
    </div>
  </div>;
}
