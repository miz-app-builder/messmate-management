import React, { useEffect, useMemo, useState } from 'react';
import { ArrowDownToLine, Check, CreditCard, Plus, Receipt, Trash2, X } from 'lucide-react';
import { supabase } from './lib/supabase';

const money = v => `৳${Number(v || 0).toLocaleString('en-BD',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
const today = () => new Date().toISOString().slice(0,10);

export default function FinancePanel({ messId, memberId, isManager=false, onClose }) {
  const [tab,setTab]=useState('expense');
  const [expenses,setExpenses]=useState([]), [deposits,setDeposits]=useState([]), [categories,setCategories]=useState([]), [members,setMembers]=useState([]);
  const [permission,setPermission]=useState({expense:false,deposit:false});
  const [expense,setExpense]=useState({category_id:'',amount:'',expense_date:today(),note:'',receipt_url:''});
  const [deposit,setDeposit]=useState({member_id:memberId||'',amount:'',deposit_date:today(),method:'',note:''});
  const [editing,setEditing]=useState(null), [busy,setBusy]=useState(false), [error,setError]=useState(''), [message,setMessage]=useState('');

  async function load(){
    if(!supabase||!messId)return;
    setError('');
    const [{data:e,error:ee},{data:d,error:de},{data:c,error:ce},{data:m,error:me}] = await Promise.all([
      supabase.from('expenses').select('id,category_id,amount,expense_date,description,bazar_entry_id,created_by,created_at,updated_at,status').eq('mess_id',messId).order('expense_date',{ascending:false}).order('created_at',{ascending:false}),
      supabase.from('deposits').select('id,member_id,amount,deposited_on,payment_method,note,recorded_by,created_at,status').eq('mess_id',messId).order('deposited_on',{ascending:false}).order('created_at',{ascending:false}),
      supabase.from('expense_categories').select('id,name').eq('mess_id',messId).order('name'),
      supabase.from('mess_members').select('id,user_id,role,status,profiles(full_name)').eq('mess_id',messId).eq('status','active').order('created_at'),
    ]);
    if(ee||de||ce||me)setError((ee||de||ce||me)?.message||'Unable to load finance data.');
    setExpenses(e||[]);setDeposits(d||[]);setCategories(c||[]);setMembers(m||[]);
    if(memberId){
      const {data:p}=await supabase.from('member_permissions').select('can_add_expense,can_record_deposit').eq('mess_member_id',memberId).maybeSingle();
      setPermission({expense:Boolean(p?.can_add_expense),deposit:Boolean(p?.can_record_deposit)});
    }
  }
  useEffect(()=>{load()},[messId,memberId]);
  const canExpense=isManager||permission.expense, canDeposit=isManager||permission.deposit;
  const expenseTotal=useMemo(()=>expenses.filter(x=>x.status==='approved').reduce((s,x)=>s+Number(x.amount||0),0),[expenses]);
  const depositTotal=useMemo(()=>deposits.filter(x=>x.status==='approved').reduce((s,x)=>s+Number(x.amount||0),0),[deposits]);

  function resetExpense(){setExpense({category_id:'',amount:'',expense_date:today(),note:'',receipt_url:''});setEditing(null)}
  async function saveExpense(ev){
    ev.preventDefault();setBusy(true);setError('');setMessage('');
    const amount=Number(expense.amount); if(!Number.isFinite(amount)||amount<0){setBusy(false);setError('Enter a valid expense amount.');return}
    const fn=editing?'update_expense':'create_expense';
    const args=editing?{p_expense_id:editing.id,p_category_id:expense.category_id||null,p_amount:amount,p_expense_date:expense.expense_date,p_note:expense.note||null,p_receipt_url:expense.receipt_url||null}:{p_mess_id:messId,p_category_id:expense.category_id||null,p_amount:amount,p_expense_date:expense.expense_date,p_note:expense.note||null,p_receipt_url:expense.receipt_url||null};
    const {error:e}=await supabase.rpc(fn,args);setBusy(false);if(e){setError(e.message);return}setMessage(editing?'Expense updated.':'Expense recorded.');resetExpense();load();
  }
  async function voidExpense(x){const reason=window.prompt('Reason for voiding this expense (optional)','')??'';setBusy(true);const {error:e}=await supabase.rpc('void_expense',{p_expense_id:x.id,p_reason:reason||null});setBusy(false);if(e)setError(e.message);else{setMessage('Expense voided.');load()}}
  async function saveDeposit(ev){
    ev.preventDefault();setBusy(true);setError('');setMessage('');const amount=Number(deposit.amount);
    if(!deposit.member_id){setBusy(false);setError('Select a member.');return} if(!Number.isFinite(amount)||amount<=0){setBusy(false);setError('Deposit amount must be greater than zero.');return}
    const {error:e}=await supabase.rpc('create_deposit',{p_mess_id:messId,p_mess_member_id:deposit.member_id,p_amount:amount,p_deposit_date:deposit.deposit_date,p_method:deposit.method||null,p_note:deposit.note||null});setBusy(false);if(e){setError(e.message);return}setMessage('Deposit recorded.');setDeposit({member_id:memberId||'',amount:'',deposit_date:today(),method:'',note:''});load();
  }
  async function voidDeposit(x){const reason=window.prompt('Reason for voiding this deposit (optional)','')??'';setBusy(true);const {error:e}=await supabase.rpc('void_deposit',{p_deposit_id:x.id,p_reason:reason||null});setBusy(false);if(e)setError(e.message);else{setMessage('Deposit voided.');load()}}
  const categoryName=id=>categories.find(c=>c.id===id)?.name||'Other';
  const memberName=id=>{const m=members.find(x=>x.id===id);return m?.profiles?.full_name||m?.role||'Member'};

  return <div className="modal-backdrop" onClick={onClose}><div className="modal finance-modal" onClick={e=>e.stopPropagation()}>
    <button className="modal-close" onClick={onClose}><X size={18}/></button>
    <div className="modal-title"><div><h2><Receipt size={20}/> Finance</h2><p className="muted">Track mess expenses and member deposits.</p></div></div>
    <div className="finance-summary"><div><span>Approved expense</span><strong>{money(expenseTotal)}</strong></div><div><span>Approved deposits</span><strong>{money(depositTotal)}</strong></div></div>
    <div className="finance-tabs"><button className={tab==='expense'?'active':''} onClick={()=>setTab('expense')}>Expenses</button><button className={tab==='deposit'?'active':''} onClick={()=>setTab('deposit')}>Deposits</button></div>
    {error&&<div className="error-banner">{error}</div>}{message&&<div className="notice">{message}</div>}

    {tab==='expense'&&<>
      {canExpense?<form className="finance-form" onSubmit={saveExpense}><div className="form-heading"><b>{editing?'Edit expense':'Record expense'}</b>{editing&&<button type="button" className="text-button" onClick={resetExpense}>Cancel</button>}</div>
        <div className="form-grid"><label>Category<select value={expense.category_id} onChange={e=>setExpense({...expense,category_id:e.target.value})}><option value="">Other</option>{categories.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><label>Amount<input type="number" min="0" step="0.01" value={expense.amount} onChange={e=>setExpense({...expense,amount:e.target.value})} required/></label><label>Date<input type="date" value={expense.expense_date} onChange={e=>setExpense({...expense,expense_date:e.target.value})} required/></label><label className="wide-field">Description <span className="optional">Optional</span><input value={expense.note} onChange={e=>setExpense({...expense,note:e.target.value})} placeholder="Monthly electricity bill"/></label><label className="wide-field">Receipt URL <span className="optional">Optional</span><input type="url" value={expense.receipt_url} onChange={e=>setExpense({...expense,receipt_url:e.target.value})} placeholder="https://…"/></label></div>
        <button className="primary" disabled={busy}>{busy?'Saving…':editing?'Save expense':<><Plus size={16}/> Record expense</>}</button></form>:<div className="notice">You do not have permission to record expenses. Ask the manager to enable <b>can_add_expense</b>.</div>}
      <div className="finance-list">{expenses.length===0?<div className="empty-state"><Receipt size={24}/><b>No expenses</b><span>Recorded expenses will appear here.</span></div>:expenses.map(x=><div className="finance-row" key={x.id}><div><b>{money(x.amount)}</b><span>{categoryName(x.category_id)} · {x.expense_date}{x.description?' · '+x.description:''}</span></div><span className={`finance-status ${x.status}`}>{x.status}</span><div className="row-actions">{x.status==='approved'&&canExpense&&<button className="outline" onClick={()=>{setEditing(x);setExpense({category_id:x.category_id||'',amount:String(x.amount),expense_date:x.expense_date,note:x.description||'',receipt_url:''})}}>Edit</button>}{x.status==='approved'&&isManager&&<button className="reject" disabled={busy} onClick={()=>voidExpense(x)}>Void</button>}</div></div>)}</div>
    </>}

    {tab==='deposit'&&<>
      {canDeposit?<form className="finance-form" onSubmit={saveDeposit}><div className="form-heading"><b>Record member deposit</b></div><div className="form-grid"><label>Member<select value={deposit.member_id} onChange={e=>setDeposit({...deposit,member_id:e.target.value})}>{members.map(m=><option key={m.id} value={m.id}>{memberName(m.id)}</option>)}</select></label><label>Amount<input type="number" min="0.01" step="0.01" value={deposit.amount} onChange={e=>setDeposit({...deposit,amount:e.target.value})} required/></label><label>Date<input type="date" value={deposit.deposit_date} onChange={e=>setDeposit({...deposit,deposit_date:e.target.value})}/></label><label>Method<input value={deposit.method} onChange={e=>setDeposit({...deposit,method:e.target.value})} placeholder="Cash / bKash / Bank"/></label><label className="wide-field">Note <span className="optional">Optional</span><input value={deposit.note} onChange={e=>setDeposit({...deposit,note:e.target.value})}/></label></div><button className="primary" disabled={busy}>{busy?'Saving…':<><ArrowDownToLine size={16}/> Record deposit</>}</button></form>:<div className="notice">You do not have permission to record deposits. Ask the manager to enable <b>can_record_deposit</b>.</div>}
      <div className="finance-list">{deposits.length===0?<div className="empty-state"><CreditCard size={24}/><b>No deposits</b><span>Member payments will appear here.</span></div>:deposits.map(x=><div className="finance-row" key={x.id}><div><b>{money(x.amount)}</b><span>{memberName(x.member_id)} · {x.deposited_on} · {x.payment_method||'Method not set'}{x.note?' · '+x.note:''}</span></div><span className={`finance-status ${x.status}`}>{x.status}</span>{isManager&&x.status==='approved'&&<button className="reject" disabled={busy} onClick={()=>voidDeposit(x)}>Void</button>}</div>)}</div>
    </>}
  </div></div>
}
