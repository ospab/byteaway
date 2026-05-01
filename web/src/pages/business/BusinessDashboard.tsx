import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  createBusinessToken,
  createCredential,
  fetchBalance,
  listBusinessTokens,
  listCredentials,
  revokeBusinessToken,
  type BusinessToken,
  type CreateCredentialPayload,
} from '../../api/client';
import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';

const TOKEN_KEY = 'byteaway_bearer_token';
const BUSINESS_SESSION_TOKEN_KEY = 'byteaway_business_session_token';

export default function BusinessDashboard() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const qc = useQueryClient();
  const [activeTab, setActiveTab] = useState<'overview' | 'tokens' | 'credentials' | 'billing'>('overview');
  const [token, setToken] = useState<string>(() => localStorage.getItem(TOKEN_KEY) || '');
  const [newCredLabel, setNewCredLabel] = useState('');
  const [country, setCountry] = useState('US');
  const [newTokenLabel, setNewTokenLabel] = useState('');
  const sessionToken = localStorage.getItem(BUSINESS_SESSION_TOKEN_KEY) || '';

  useEffect(() => {
    if (token) localStorage.setItem(TOKEN_KEY, token);
  }, [token]);

  const enabled = useMemo(() => token.trim().length > 0, [token]);

  const balanceQuery = useQuery({
    queryKey: ['balance', token],
    queryFn: () => fetchBalance(token),
    enabled
  });

  const credentialsQuery = useQuery({
    queryKey: ['credentials', token],
    queryFn: () => listCredentials(token),
    enabled
  });

  const businessTokensQuery = useQuery({
    queryKey: ['business-tokens', sessionToken],
    queryFn: () => listBusinessTokens(sessionToken),
    enabled: sessionToken.length > 0,
  });

  const createMutation = useMutation({
    mutationFn: (payload: CreateCredentialPayload) => createCredential(token, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['credentials', token] });
      setNewCredLabel('');
    }
  });

  const registerTokenMutation = useMutation({
    mutationFn: () => createBusinessToken(sessionToken, {
      label: newTokenLabel || undefined,
      country,
    }),
    onSuccess: (result) => {
      setToken(result.token);
      setNewTokenLabel('');
      qc.invalidateQueries({ queryKey: ['business-tokens', sessionToken] });
      qc.invalidateQueries({ queryKey: ['balance', result.token] });
      qc.invalidateQueries({ queryKey: ['credentials', result.token] });
    },
  });

  const revokeTokenMutation = useMutation({
    mutationFn: (credentialId: string) => revokeBusinessToken(sessionToken, credentialId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['business-tokens', sessionToken] });
    }
  });

  const tokensCount = (businessTokensQuery.data as BusinessToken[] | undefined)?.length ?? 0;
  const credentialsCount = credentialsQuery.data?.length ?? 0;

  const tabs = [
    { key: 'overview' as const, label: lang === 'ru' ? 'Сводка' : 'Overview' },
    { key: 'tokens' as const, label: lang === 'ru' ? 'API Токены' : 'API Tokens' },
    { key: 'credentials' as const, label: lang === 'ru' ? 'Доступы' : 'Credentials' },
    { key: 'billing' as const, label: lang === 'ru' ? 'Финансы' : 'Financials' },
  ];

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
             <h1 className="text-3xl font-display font-bold text-white">{lang === 'ru' ? 'Консоль управления' : 'Management Console'}</h1>
             <span className={`px-2 py-0.5 rounded-md text-[10px] font-black uppercase tracking-widest ${enabled ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'}`}>
                {enabled ? 'Online' : 'Restricted'}
             </span>
          </div>
          <p className="text-slate-500 text-sm max-w-xl">
            {lang === 'ru'
              ? 'Единый центр управления сетевой инфраструктурой, авторизацией и балансом вашей компании.'
              : 'Central hub for network infrastructure, authorization, and corporate balance management.'}
          </p>
        </div>

        <nav className="flex items-center p-1 bg-white/5 rounded-xl border border-white/5">
           {tabs.map((t) => (
             <button
               key={t.key}
               onClick={() => setActiveTab(t.key)}
               className={`px-4 py-2 rounded-lg text-xs font-bold uppercase tracking-wider transition-all ${activeTab === t.key ? 'bg-white text-ink shadow-lg shadow-white/10' : 'text-slate-500 hover:text-slate-300'}`}
             >
               {t.label}
             </button>
           ))}
        </nav>
      </div>

      <div className="w-full h-px bg-gradient-to-r from-transparent via-white/5 to-transparent" />

      {activeTab === 'overview' && (
        <div className="space-y-8 animate-in fade-in duration-500">
          <div className="grid gap-6 md:grid-cols-3">
             <StatsCard 
                label={lang === 'ru' ? 'Активные токены' : 'Active Tokens'} 
                value={tokensCount.toString()} 
                sub={lang === 'ru' ? 'Всего выпущено API-ключей' : 'Total issued API keys'} 
             />
             <StatsCard 
                label={lang === 'ru' ? 'Рабочие доступы' : 'Live Credentials'} 
                value={credentialsCount.toString()} 
                sub={lang === 'ru' ? 'Активные сессии и доступы' : 'Active sessions and credentials'} 
             />
             <StatsCard 
                label={lang === 'ru' ? 'Текущий баланс' : 'Current Balance'} 
                value={balanceQuery.data ? `$${balanceQuery.data.balance_usd.toFixed(2)}` : '—'} 
                sub={lang === 'ru' ? 'Доступные средства на счете' : 'Available funds in USD'} 
                highlight
             />
          </div>

          <div className="grid gap-6 md:grid-cols-2">
             <div className="card space-y-6">
                <div>
                   <h3 className="text-lg font-bold text-white mb-1">{lang === 'ru' ? 'Workspace Токен' : 'Workspace Token'}</h3>
                   <p className="text-xs text-slate-500">{lang === 'ru' ? 'Используйте Bearer-токен для разблокировки административных действий.' : 'Use your Bearer token to unlock administrative actions.'}</p>
                </div>
                <div className="relative group">
                   <input
                     className="input font-mono !pr-12 text-sm"
                     value={token}
                     onChange={(e) => setToken(e.target.value)}
                     placeholder="sk_live_..."
                     type="password"
                   />
                   <div className="absolute right-4 top-1/2 -translate-y-1/2 opacity-20 group-hover:opacity-100 transition-opacity pointer-events-none">
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>
                   </div>
                </div>
             </div>

             <div className="card space-y-6">
                <div>
                   <h3 className="text-lg font-bold text-white mb-1">{lang === 'ru' ? 'Профиль региона' : 'Regional Profile'}</h3>
                   <p className="text-xs text-slate-500">{lang === 'ru' ? 'Укажите предпочтительную локацию для новых ресурсов.' : 'Set the preferred location for new resources.'}</p>
                </div>
                <select className="input text-sm appearance-none cursor-pointer" value={country} onChange={(e) => setCountry(e.target.value)}>
                   <option value="US">🇺🇸 United States (Global)</option>
                   <option value="DE">🇩🇪 Germany (Europe)</option>
                   <option value="RU">🇷🇺 Russia (Local)</option>
                   <option value="SG">🇸🇬 Singapore (Asia)</option>
                </select>
             </div>
          </div>
        </div>
      )}

      {activeTab === 'tokens' && (
        <div className="space-y-8 animate-in slide-in-from-bottom-4 duration-500">
           <div className="card space-y-6">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                 <div>
                    <h3 className="text-xl font-bold text-white">{lang === 'ru' ? 'Выпуск API-токена' : 'Issue API Token'}</h3>
                    <p className="text-sm text-slate-500">{lang === 'ru' ? 'Создайте новый ключ для программного доступа к сети.' : 'Create a new key for programmatic network access.'}</p>
                 </div>
                 <button
                    className="btn-primary !py-2.5 shadow-xl shadow-white/5"
                    onClick={() => registerTokenMutation.mutate()}
                    disabled={registerTokenMutation.isPending || !sessionToken}
                  >
                    {registerTokenMutation.isPending ? '...' : (lang === 'ru' ? 'Сгенерировать ключ' : 'Generate Key')}
                 </button>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                 <input
                    className="input text-sm"
                    value={newTokenLabel}
                    onChange={(e) => setNewTokenLabel(e.target.value)}
                    placeholder={lang === 'ru' ? 'Метка (например, PROD-01)' : 'Label (e.g. PROD-01)'}
                 />
                 <select className="input text-sm" value={country} onChange={(e) => setCountry(e.target.value)}>
                    <option value="US">USA</option>
                    <option value="DE">Germany</option>
                    <option value="RU">Russia</option>
                    <option value="SG">Singapore</option>
                 </select>
              </div>

              {registerTokenMutation.isSuccess && (
                <div className="p-6 rounded-2xl bg-accent/5 border border-accent/20 space-y-4 animate-in zoom-in-95">
                  <div className="flex items-center gap-2 text-accent">
                     <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
                     <span className="font-bold text-sm uppercase tracking-widest">{lang === 'ru' ? 'Ключ успешно создан' : 'Token successfully issued'}</span>
                  </div>
                  <div className="grid gap-3 font-mono text-xs text-slate-300">
                    <div className="p-3 bg-black/40 rounded-lg border border-white/5 break-all select-all">{registerTokenMutation.data.token}</div>
                  </div>
                  <p className="text-[10px] text-amber-400 font-bold uppercase">{lang === 'ru' ? 'Скопируйте сейчас. Токен не будет показан повторно.' : 'Copy now. The token will not be shown again.'}</p>
                </div>
              )}
           </div>

           <div className="card space-y-6">
              <h3 className="text-lg font-bold text-white">{lang === 'ru' ? 'Реестр токенов' : 'Token Registry'}</h3>
              <div className="overflow-x-auto">
                 <table className="w-full text-left">
                    <thead>
                       <tr>
                          <th className="table-header">{lang === 'ru' ? 'Идентификатор' : 'Identifier'}</th>
                          <th className="table-header">{lang === 'ru' ? 'Метка' : 'Label'}</th>
                          <th className="table-header">{lang === 'ru' ? 'Дата создания' : 'Created At'}</th>
                          <th className="table-header text-right">{lang === 'ru' ? 'Управление' : 'Actions'}</th>
                       </tr>
                    </thead>
                    <tbody>
                       {businessTokensQuery.data?.map((t) => (
                         <tr key={t.credential_id}>
                            <td className="table-cell font-mono text-xs">{t.username}</td>
                            <td className="table-cell">{t.label || '—'}</td>
                            <td className="table-cell text-slate-500">{new Date(t.created_at).toLocaleDateString()}</td>
                            <td className="table-cell text-right">
                               <button 
                                  onClick={() => revokeTokenMutation.mutate(t.credential_id)}
                                  className="text-red-500/50 hover:text-red-500 text-[10px] uppercase font-bold tracking-widest transition-colors"
                               >
                                  {lang === 'ru' ? 'Отозвать' : 'Revoke'}
                               </button>
                            </td>
                         </tr>
                       ))}
                    </tbody>
                 </table>
              </div>
           </div>
        </div>
      )}

      {activeTab === 'credentials' && (
        <div className="space-y-8 animate-in slide-in-from-bottom-4 duration-500">
           {/* Credentials implementation upgraded similarly... */}
           <div className="card space-y-6">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                 <div>
                    <h3 className="text-xl font-bold text-white">{lang === 'ru' ? 'Выдача доступа' : 'Issue Credential'}</h3>
                    <p className="text-sm text-slate-500">{lang === 'ru' ? 'Создайте учетные данные для SOCKS5/HTTP прокси.' : 'Create credentials for SOCKS5/HTTP proxy.'}</p>
                 </div>
                 <button
                    className="btn-primary !py-2.5"
                    onClick={() => createMutation.mutate({ label: newCredLabel || undefined, country })}
                    disabled={createMutation.isPending || !enabled}
                  >
                    {createMutation.isPending ? '...' : (lang === 'ru' ? 'Создать' : 'Create')}
                 </button>
              </div>
              <div className="grid gap-4 md:grid-cols-2">
                 <input
                    className="input text-sm"
                    value={newCredLabel}
                    onChange={(e) => setNewCredLabel(e.target.value)}
                    placeholder="Label (e.g. Crawler-DE)"
                 />
                 <select className="input text-sm" value={country} onChange={(e) => setCountry(e.target.value)}>
                    <option value="US">USA</option>
                    <option value="DE">Germany</option>
                    <option value="RU">Russia</option>
                    <option value="SG">Singapore</option>
                 </select>
              </div>

              {createMutation.isSuccess && (
                <div className="p-6 rounded-2xl bg-white/5 border border-white/10 space-y-4 animate-in zoom-in-95">
                  <div className="grid grid-cols-2 gap-4">
                     <CredentialItem label="Username" value={createMutation.data.username} />
                     <CredentialItem label="Password" value={createMutation.data.password} />
                     <CredentialItem label="Proxy Host" value={createMutation.data.proxy_host} />
                     <CredentialItem label="Proxy Port" value={createMutation.data.proxy_port.toString()} />
                  </div>
                </div>
              )}
           </div>

           <div className="card space-y-6">
              <h3 className="text-lg font-bold text-white">{lang === 'ru' ? 'Активные доступы' : 'Active Credentials'}</h3>
              <div className="overflow-x-auto">
                 <table className="w-full text-left">
                    <thead>
                       <tr>
                          <th className="table-header">Username</th>
                          <th className="table-header">Label</th>
                          <th className="table-header">Status</th>
                       </tr>
                    </thead>
                    <tbody>
                       {credentialsQuery.data?.map((c) => (
                         <tr key={c.credential_id}>
                            <td className="table-cell font-mono text-xs">{c.username}</td>
                            <td className="table-cell">{c.label || '—'}</td>
                            <td className="table-cell">
                               <span className="flex items-center gap-1.5 text-[10px] uppercase font-black text-emerald-400">
                                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.5)]" />
                                  Active
                               </span>
                            </td>
                         </tr>
                       ))}
                    </tbody>
                 </table>
              </div>
           </div>
        </div>
      )}

      {activeTab === 'billing' && (
        <div className="grid gap-6 md:grid-cols-2 animate-in fade-in duration-500">
           <div className="card space-y-8 bg-gradient-to-br from-slate-900/40 to-ink">
              <div>
                 <h3 className="text-xl font-bold text-white mb-2">{lang === 'ru' ? 'Баланс счета' : 'Account Balance'}</h3>
                 <p className="text-slate-500 text-sm leading-relaxed">{lang === 'ru' ? 'Средства используются для оплаты трафика ваших узлов и аренды выделенных портов.' : 'Funds are used for your nodes\' traffic and dedicated port leases.'}</p>
              </div>
              <div className="space-y-2">
                 <div className="text-5xl font-display font-bold text-white">${balanceQuery.data?.balance_usd.toFixed(2) ?? '0.00'}</div>
                 <div className="text-[10px] uppercase tracking-widest text-slate-600 font-bold">Client ID: {balanceQuery.data?.client_id ?? '—'}</div>
              </div>
              <button className="btn-ghost w-full !border-white/5 !bg-white/5 text-slate-300 pointer-events-none">
                 {lang === 'ru' ? 'Пополнение временно через поддержку' : 'Top-up via support currently'}
              </button>
           </div>

           <div className="card space-y-6">
              <h3 className="text-lg font-bold text-white">{lang === 'ru' ? 'Финансовые операции' : 'Financial Operations'}</h3>
              <div className="space-y-4">
                 <OperationOption 
                    title={lang === 'ru' ? 'Автоматизация' : 'Automation'} 
                    text={lang === 'ru' ? 'Привязка банковских карт для автоматического пополнения при низком остатке.' : 'Link bank cards for automated top-up on low balance.'}
                    disabled
                 />
                 <OperationOption 
                    title={lang === 'ru' ? 'Документация' : 'Invoicing'} 
                    text={lang === 'ru' ? 'Формирование актов и счетов для юридических лиц.' : 'Generate acts and invoices for legal entities.'}
                    disabled
                 />
              </div>
           </div>
        </div>
      )}
    </div>
  );
}

function StatsCard({ label, value, sub, highlight }: { label: string, value: string, sub: string, highlight?: boolean }) {
  return (
    <div className={`card space-y-3 ${highlight ? 'bg-white/5 border-white/10' : ''}`}>
       <div className="text-[10px] uppercase tracking-widest font-black text-slate-500">{label}</div>
       <div className={`text-4xl font-display font-bold ${highlight ? 'text-white' : 'text-slate-200'}`}>{value}</div>
       <div className="text-[11px] text-slate-500 leading-tight">{sub}</div>
    </div>
  );
}

function CredentialItem({ label, value }: { label: string, value: string }) {
  return (
    <div className="space-y-1">
       <div className="text-[10px] uppercase tracking-widest font-bold text-slate-600">{label}</div>
       <div className="p-2.5 bg-black/40 border border-white/5 rounded-lg text-xs font-mono text-slate-300 break-all select-all">{value}</div>
    </div>
  );
}

function OperationOption({ title, text, disabled }: { title: string, text: string, disabled?: boolean }) {
  return (
    <div className={`p-4 rounded-xl border border-white/5 bg-white/[0.02] ${disabled ? 'opacity-50' : ''}`}>
       <div className="font-bold text-sm text-white mb-1 flex items-center justify-between">
          {title}
          {disabled && <span className="text-[8px] bg-white/10 px-1.5 py-0.5 rounded uppercase tracking-tighter">Planned</span>}
       </div>
       <p className="text-xs text-slate-500 leading-relaxed">{text}</p>
    </div>
  );
}
