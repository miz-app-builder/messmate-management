import React from 'react';
import { Bell, ChevronRight, CircleDollarSign, Coffee, Home, Menu, Plus, ShoppingBasket, Utensils, Wallet } from 'lucide-react';

const meals = [
  { name: 'Breakfast', time: '8:00 AM', status: 'Confirmed', value: 1 },
  { name: 'Lunch', time: '1:30 PM', status: 'Confirmed', value: 1 },
  { name: 'Dinner', time: '8:30 PM', status: 'Off', value: 0 },
];

function Stat({ icon: Icon, label, value, hint }) {
  return <div className="stat-card"><div className="stat-icon"><Icon size={19} /></div><div><p>{label}</p><strong>{value}</strong><span>{hint}</span></div></div>;
}

export default function App() {
  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand"><div className="brand-mark"><Utensils size={19} /></div><div><b>MessMate</b><small>Mess management</small></div></div>
        <div className="top-actions"><button className="icon-button" aria-label="Notifications"><Bell size={19} /></button><div className="avatar">M</div></div>
      </header>

      <main className="content">
        <section className="welcome-row"><div><p className="eyebrow">THURSDAY, 17 SEPTEMBER</p><h1>Good evening, Masud 👋</h1><p className="muted">Sreepur Bachelor Mess · Active member</p></div><button className="primary"><Plus size={18} /> Add</button></section>

        <section className="stats-grid">
          <Stat icon={Utensils} label="Today's meals" value="2" hint="of 3 meal slots" />
          <Stat icon={CircleDollarSign} label="Meal rate" value="৳30.00" hint="current rate" />
          <Stat icon={Wallet} label="My balance" value="৳1,650" hint="available advance" />
        </section>

        <section className="grid-2">
          <div className="panel">
            <div className="panel-head"><div><h2>Today's meals</h2><p>Tap a meal to view its status</p></div><button className="text-button">Meal history <ChevronRight size={16} /></button></div>
            <div className="meal-list">{meals.map((meal) => <div className="meal-row" key={meal.name}><div className={`meal-icon ${meal.status === 'Off' ? 'off' : ''}`}><Coffee size={18} /></div><div className="meal-info"><b>{meal.name}</b><span>{meal.time}</span></div><div className={`status ${meal.status === 'Off' ? 'status-off' : 'status-on'}`}>{meal.status}</div><strong className="meal-value">{meal.value}</strong></div>)}</div>
          </div>

          <div className="panel tomorrow">
            <div className="panel-head"><div><h2>Tomorrow's meals</h2><p>Confirm before the cut-off</p></div><span className="lock-note">Cut-off 10:00 PM</span></div>
            <div className="tomorrow-card"><div><b>Friday, 18 September</b><span>All meals default to ON if unconfirmed</span></div><button className="outline">Manage</button></div>
            <div className="mini-summary"><div><span>Breakfast</span><b>ON</b></div><div><span>Lunch</span><b>ON</b></div><div><span>Dinner</span><b>ON</b></div></div>
          </div>
        </section>

        <section className="quick-section"><div className="section-title"><div><h2>Quick actions</h2><p>Common tasks, one tap away</p></div></div><div className="quick-grid"><button><Utensils size={19} /><span>Meal Off</span><small>Set your off days</small></button><button><ShoppingBasket size={19} /><span>Bazar</span><small>Add or view entries</small></button><button><Wallet size={19} /><span>Deposit</span><small>Record payment</small></button><button><CircleDollarSign size={19} /><span>My ledger</span><small>See full account</small></button></div></section>
      </main>

      <nav className="bottom-nav"><a className="active"><Home size={19} /><span>Home</span></a><a><Utensils size={19} /><span>Meals</span></a><a><ShoppingBasket size={19} /><span>Bazar</span></a><a><Wallet size={19} /><span>Ledger</span></a><a><Menu size={19} /><span>More</span></a></nav>
    </div>
  );
}
