import React from 'react';
import { createRoot } from 'react-dom/client';
import AppShell from './AppShell.jsx';
import './styles.css';
import './meal.css';
import './bazar.css';
import './finance.css';
import './ledger.css';
import './settlement.css';
import './reports.css';
import './notifications.css';
import './ui-overrides.css';

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <AppShell />
  </React.StrictMode>
);
