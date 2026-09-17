import React, { useEffect, useMemo, useState } from 'react';
import { Check, Clock3, Plus, Receipt, ShoppingBasket, Trash2, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money = (v) => `৳${Number(v || 0).toLocaleString('en-BD', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const today = () => new Date().toISOString().slice(0, 10);
const emptyForm = () => ({ purchased_on: today(), note: '', receipt_url: '' });
const emptyItem = () => ({ item_name: '', quantity: '1', unit: 'kg', unit_price: '' });

function StatusBadge({ status }) {
  const label = status === 'approved' ? 'Approved' : status === 'rejected' ? 'Rejected' : 'Pending';
  return <span className={`bazar-status bazar-status-${status}`}>
    {status === 'approved' ? <Check size={13} /> : status === 'rejected' ? <X size={13} /> : <Clock3 size={13} />}
    {label}
  </span>;
}

export default function BazarPanel({ messId, memberId, isManager = false, onClose }) {
  const [entries, setEntries] = useState([]);
  const [items, setItems] = useState({});
  const [permission, setPermission] = useState({ add: false, approve: false });
  const [approvalRequired, setApprovalRequired] = useState(true);
  const [form, setForm] = useState(emptyForm());
  const [itemForm, setItemForm] = useState(emptyItem());
  const [editing, setEditing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const load = async () => {
    if (!supabase || !messId) return;
    setError('');
    const [{ data: e, error: ee }, { data: s, error: se }] = await Promise.all([
      supabase.from('bazar_entries').select('id,buyer_member_id,purchased_on,total_amount,status,note,receipt_url,approved_at,approved_by,created_at,updated_at').eq('mess_id', messId).order('purchased_on', { ascending: false }).order('created_at', { ascending: false }),
      supabase.from('mess_settings').select('bazar_approval_required').eq('mess_id', messId).maybeSingle(),
    ]);
    if (ee || se) setError((ee || se).message);
    setEntries(e || []);
    setApprovalRequired(s?.bazar_approval_required ?? true);
    const ids = (e || []).map(x => x.id);
    if (ids.length) {
      const { data: mi, error: me } = await supabase.from('bazar_items').select('id,bazar_entry_id,item_name,quantity,unit,unit_price').in('bazar_entry_id', ids);
      if (me) setError(me.message);
      const grouped = {};
      (mi || []).forEach(x => { (grouped[x.bazar_entry_id] ||= []).push(x); });
      setItems(grouped);
    } else setItems({});
    if (memberId) {
      const { data: mp } = await supabase.from('member_permissions').select('can_add_bazar,can_approve_bazar').eq('mess_member_id', memberId).maybeSingle();
      setPermission({ add: Boolean(mp?.can_add_bazar), approve: Boolean(mp?.can_approve_bazar) });
    }
  };

  useEffect(() => { load(); }, [messId, memberId]);

  // Managers are implicit full-permission actors; delegated members use their
  // explicit member_permissions grant.
  const canAdd = isManager || permission.add;
  const canApprove = permission.approve || isManager;
  const pendingCount = useMemo(() => entries.filter(x => x.status === 'pending').length, [entries]);
  const approvedTotal = useMemo(() => entries.filter(x => x.status === 'approved').reduce((s, x) => s + Number(x.total_amount || 0), 0), [entries]);
  const draftItemTotal = Number(itemForm.quantity || 0) * Number(itemForm.unit_price || 0);

  async function addItem(entryId) {
    const qty = Number(itemForm.quantity), price = Number(itemForm.unit_price);
    if (!itemForm.item_name.trim()) { setError('Item name is required.'); return; }
    if (!Number.isFinite(qty) || qty <= 0) { setError('Quantity must be greater than zero.'); return; }
    if (!Number.isFinite(price) || price < 0) { setError('Unit price cannot be negative.'); return; }
    setBusy(true); setError(''); setMessage('');
    const { error: e } = await supabase.rpc('add_bazar_item', { p_bazar_entry_id: entryId, p_item_name: itemForm.item_name.trim(), p_quantity: qty, p_unit: itemForm.unit.trim() || null, p_unit_price: price });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setItemForm(emptyItem());
    await load();
  }

  async function deleteItem(item) {
    if (!window.confirm(`Delete ${item.item_name}?`)) return;
    setBusy(true); setError('');
    const { error: e } = await supabase.rpc('delete_bazar_item', { p_item_id: item.id });
    setBusy(false);
    if (e) { setError(e.message); return; }
    await load();
  }

  async function submit(e) {
    e.preventDefault();
    if (!supabase) return;
    setBusy(true); setError(''); setMessage('');

    if (editing) {
      const currentTotal = (items[editing.id] || []).reduce((s, x) => s + Number(x.quantity || 0) * Number(x.unit_price || 0), 0);
      const result = await supabase.rpc('update_bazar_entry', { p_entry_id: editing.id, p_purchased_on: form.purchased_on, p_total_amount: currentTotal, p_note: form.note || null, p_receipt_url: form.receipt_url || null });
      setBusy(false);
      if (result.error) { setError(result.error.message); return; }
      setMessage('Bazar entry updated.');
      setEditing(null); setForm(emptyForm()); setItemForm(emptyItem()); await load();
      return;
    }

    // New entries are created atomically with their first item. This prevents
    // approval-off mode from creating an empty already-approved entry.
    const qty = Number(itemForm.quantity), price = Number(itemForm.unit_price);
    if (!itemForm.item_name.trim()) { setBusy(false); setError('Item name is required.'); return; }
    if (!Number.isFinite(qty) || qty <= 0) { setBusy(false); setError('Quantity must be greater than zero.'); return; }
    if (!Number.isFinite(price) || price < 0) { setBusy(false); setError('Unit price cannot be negative.'); return; }

    const result = await supabase.rpc('create_bazar_entry_with_items', {
      p_mess_id: messId,
      p_purchased_on: form.purchased_on,
      p_note: form.note || null,
      p_receipt_url: form.receipt_url || null,
      p_items: [{ item_name: itemForm.item_name.trim(), quantity: qty, unit: itemForm.unit.trim() || null, unit_price: price }],
    });
    setBusy(false);
    if (result.error) { setError(result.error.message); return; }
    setMessage(approvalRequired ? 'Bazar entry created and sent for approval.' : 'Bazar entry created and approved.');
    setForm(emptyForm()); setItemForm(emptyItem()); setEditing(null); await load();
  }

  async function review(entry, decision) {
    const reason = window.prompt(decision === 'approved' ? 'Approval note (optional)' : 'Rejection reason (optional)', '') ?? '';
    setBusy(true); setError(''); setMessage('');
    const { error: e } = await supabase.rpc('review_bazar_entry', { p_entry_id: entry.id, p_decision: decision, p_reason: reason || null });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setMessage(`Entry ${decision}.`); await load();
  }

  async function toggleApproval() {
    setBusy(true); setError(''); setMessage('');
    const { error: e } = await supabase.rpc('set_bazar_approval_required', { p_mess_id: messId, p_enabled: !approvalRequired });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setApprovalRequired(!approvalRequired); setMessage(`Bazar approval ${!approvalRequired ? 'enabled' : 'disabled'}.`);
  }

  function startEdit(entry) {
    setEditing(entry); setForm({ purchased_on: entry.purchased_on || today(), note: entry.note || '', receipt_url: entry.receipt_url || '' }); setItemForm(emptyItem()); setMessage(''); setError('');
  }

  return <div className="modal-backdrop" onClick={onClose}>
    <div className="modal bazar-modal" onClick={e => e.stopPropagation()}>
      <button className="modal-close" onClick={onClose}><X size={18} /></button>
      <div className="modal-title"><div><h2><ShoppingBasket size={20} /> Bazar</h2><p className="muted">Record shared grocery and market purchases item by item.</p></div><span className="count-badge">{pendingCount} pending</span></div>
      <div className="bazar-summary"><div><span>Approved spend</span><strong>{money(approvedTotal)}</strong></div><div><span>Approval</span><strong>{approvalRequired ? 'Required' : 'Auto-approve'}</strong></div></div>

      {canAdd && <form className="bazar-form" onSubmit={submit}>
        <div className="form-heading"><b>{editing ? 'Edit bazar entry' : 'New bazar entry'}</b>{editing && <button type="button" className="text-button" onClick={() => { setEditing(null); setForm(emptyForm()); setItemForm(emptyItem()); }}>Close editor</button>}</div>
        <div className="form-grid">
          <label>Purchase date<input type="date" value={form.purchased_on} onChange={e => setForm({ ...form, purchased_on: e.target.value })} required /></label>
          <label>Item name<input value={itemForm.item_name} onChange={e => setItemForm({ ...itemForm, item_name: e.target.value })} placeholder="Rice" required={!editing} /></label>
          <label>Qty<input type="number" min="0.001" step="0.001" value={itemForm.quantity} onChange={e => setItemForm({ ...itemForm, quantity: e.target.value })} /></label>
          <label>Unit<input value={itemForm.unit} onChange={e => setItemForm({ ...itemForm, unit: e.target.value })} placeholder="kg" /></label>
          <label>Unit price<input type="number" min="0" step="0.01" value={itemForm.unit_price} onChange={e => setItemForm({ ...itemForm, unit_price: e.target.value })} placeholder="0.00" required={!editing} /></label>
          <label className="wide-field">Note <span className="optional">Optional</span><input value={form.note} onChange={e => setForm({ ...form, note: e.target.value })} placeholder="e.g. Weekly grocery" /></label>
          <label className="wide-field">Receipt URL <span className="optional">Optional</span><input type="url" value={form.receipt_url} onChange={e => setForm({ ...form, receipt_url: e.target.value })} placeholder="https://…" /></label>
        </div>
        {!editing && <div className="item-total-preview">Line total: <b>{money(draftItemTotal)}</b></div>}
        <button className="primary" disabled={busy}>{busy ? 'Saving…' : editing ? 'Save entry details' : <><Plus size={16} /> Create bazar entry</>}</button>
      </form>}

      {!canAdd && <div className="notice"><Receipt size={14} /> You do not currently have permission to add bazar entries. Ask the manager to enable <b>can_add_bazar</b>.</div>}
      {error && <div className="error-banner">{error}</div>}
      {message && <div className="notice">{message}</div>}

      {isManager && <div className="bazar-admin-row"><div><b>Approval required</b><span>{approvalRequired ? 'New entries wait for approval.' : 'New entries are automatically approved.'}</span></div><button className="outline" disabled={busy} onClick={toggleApproval}>{approvalRequired ? 'Turn off' : 'Turn on'}</button></div>}

      <div className="bazar-list">
        {entries.length === 0 ? <div className="empty-state"><ShoppingBasket size={24} /><b>No bazar entries</b><span>Approved purchases will appear here.</span></div> : entries.map(entry => {
          const mine = entry.buyer_member_id === memberId;
          const canEdit = mine && entry.status !== 'approved' && canAdd;
          const entryItems = items[entry.id] || [];
          const calculatedTotal = entryItems.reduce((s, x) => s + Number(x.quantity || 0) * Number(x.unit_price || 0), 0);
          return <div className="bazar-entry" key={entry.id}>
            <div className="bazar-entry-main"><div><b>{money(entry.total_amount)}</b><span>{entry.purchased_on} · {entry.note || 'No note'}</span></div><StatusBadge status={entry.status} /></div>
            {entryItems.length > 0 && <div className="bazar-items"><div className="bazar-items-head"><b>Items</b><strong>{money(calculatedTotal)}</strong></div>{entryItems.map(item => <div className="bazar-item" key={item.id}><div><b>{item.item_name}</b><span>{item.quantity} {item.unit || ''} × {money(item.unit_price)}</span></div>{canEdit && <button className="icon-button" disabled={busy} title="Delete item" onClick={() => deleteItem(item)}><Trash2 size={15} /></button>}</div>)}</div>}
            {editing?.id === entry.id && canEdit && entry.status !== 'approved' && <div className="bazar-item-form"><div className="item-form-title"><b>Add item to entry</b><span>Line total: {money(draftItemTotal)}</span></div><div className="form-grid"><label>Item name<input value={itemForm.item_name} onChange={e => setItemForm({ ...itemForm, item_name: e.target.value })} placeholder="Rice" /></label><label>Qty<input type="number" min="0.001" step="0.001" value={itemForm.quantity} onChange={e => setItemForm({ ...itemForm, quantity: e.target.value })} /></label><label>Unit<input value={itemForm.unit} onChange={e => setItemForm({ ...itemForm, unit: e.target.value })} placeholder="kg" /></label><label>Unit price<input type="number" min="0" step="0.01" value={itemForm.unit_price} onChange={e => setItemForm({ ...itemForm, unit_price: e.target.value })} placeholder="0.00" /></label></div><button type="button" className="primary" disabled={busy} onClick={() => addItem(entry.id)}><Plus size={16} /> Add item</button></div>}
            <div className="bazar-entry-actions">{entry.receipt_url && <a href={entry.receipt_url} target="_blank" rel="noreferrer">Receipt</a>}{canEdit && <button className="outline" disabled={busy} onClick={() => startEdit(entry)}>{editing?.id === entry.id ? 'Editing' : 'Edit'}</button>}{canApprove && entry.status === 'pending' && <><button className="reject" disabled={busy} onClick={() => review(entry, 'rejected')}>Reject</button><button className="approve" disabled={busy} onClick={() => review(entry, 'approved')}><Check size={14} /> Approve</button></>}</div>
          </div>;
        })}
      </div>
    </div>
  </div>;
}
