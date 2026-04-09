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
    {
      key: 'overview' as const,
      ru: 'Обзор',
      en: 'Overview',
    },
    {
      key: 'tokens' as const,
      ru: 'Токены',
      en: 'Tokens',
    },
    {
      key: 'credentials' as const,
      ru: 'Доступы',
      en: 'Credentials',
    },
    {
      key: 'billing' as const,
      ru: 'Платежи',
      en: 'Billing',
    },
  ];

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold text-white">{lang === 'ru' ? 'Рабочий кабинет' : 'Operations console'}</h1>
        <p className="text-slate-400">
          {lang === 'ru'
            ? 'Управляйте доступами, контролируйте баланс и поддерживайте рабочие операции команды.'
            : 'Manage access, control balance, and run day-to-day team operations.'}
        </p>
      </div>

      <div className="card p-2">
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`rounded-lg px-3 py-2 text-sm font-medium transition ${
                activeTab === tab.key
                  ? 'bg-cyan-500/20 text-cyan-200 border border-cyan-400/50'
                  : 'bg-slate-900/40 text-slate-300 border border-slate-800 hover:border-slate-700'
              }`}
            >
              {lang === 'ru' ? tab.ru : tab.en}
            </button>
          ))}
        </div>
      </div>

      {activeTab === 'overview' && (
        <>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="card space-y-1">
              <p className="text-xs uppercase tracking-wider text-slate-500">Auth state</p>
              <p className="text-2xl font-bold text-white">{enabled ? (lang === 'ru' ? 'Авторизован' : 'Authorized') : (lang === 'ru' ? 'Не авторизован' : 'Not authorized')}</p>
              <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Для операций управления требуется рабочий токен.' : 'A workspace token is required for management actions.'}</p>
            </div>
            <div className="card space-y-1">
              <p className="text-xs uppercase tracking-wider text-slate-500">Token records</p>
              <p className="text-2xl font-bold text-white">{tokensCount}</p>
              <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Количество выданных API-токенов.' : 'Number of issued API tokens.'}</p>
            </div>
            <div className="card space-y-1">
              <p className="text-xs uppercase tracking-wider text-slate-500">Credential records</p>
              <p className="text-2xl font-bold text-white">{credentialsCount}</p>
              <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Количество выданных рабочих доступов.' : 'Number of issued operational credentials.'}</p>
            </div>
          </div>

          <div className="card space-y-3">
            <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Рабочий токен' : 'Workspace token'}</h3>
            <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Укажите токен доступа для управленческих операций в кабинете.' : 'Provide your access token to unlock management operations.'}</p>
            <input
              className="input"
              value={token}
              onChange={(e) => setToken(e.target.value)}
              placeholder="sk_live_..."
            />
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div className="card space-y-2">
              <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Баланс' : 'Balance'}</h3>
              {balanceQuery.isLoading && <p className="text-slate-400">{lang === 'ru' ? 'Загрузка...' : 'Loading...'}</p>}
              {balanceQuery.isError && <p className="text-red-400">Error: {(balanceQuery.error as Error).message}</p>}
              {balanceQuery.data && (
                <>
                  <p className="text-4xl font-bold text-white">${balanceQuery.data.balance_usd.toFixed(2)}</p>
                  <p className="text-slate-400 text-sm">client_id: {balanceQuery.data.client_id}</p>
                </>
              )}
            </div>

            <div className="card space-y-2">
              <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Регион по умолчанию' : 'Default region'}</h3>
              <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Профиль для новых токенов и доступов.' : 'Profile used for new tokens and credentials.'}</p>
              <select className="input" value={country} onChange={(e) => setCountry(e.target.value)}>
                <option>US</option>
                <option>DE</option>
                <option>RU</option>
                <option>SG</option>
              </select>
            </div>
          </div>

          <div className="card space-y-4">
            <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'С чего начать' : 'How to start'}</h3>
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4 text-sm text-slate-300">
                <p className="text-cyan-300">1</p>
                <p className="mt-1">{lang === 'ru' ? 'Создайте API-токен во вкладке "Токены".' : 'Create an API token in the Tokens tab.'}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4 text-sm text-slate-300">
                <p className="text-cyan-300">2</p>
                <p className="mt-1">{lang === 'ru' ? 'Создайте рабочий доступ во вкладке "Доступы".' : 'Create a credential in the Credentials tab.'}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4 text-sm text-slate-300">
                <p className="text-cyan-300">3</p>
                <p className="mt-1">{lang === 'ru' ? 'Настройте пополнение во вкладке "Платежи".' : 'Set up top-ups in the Billing tab.'}</p>
              </div>
            </div>
          </div>
        </>
      )}

      {activeTab === 'tokens' && (
        <>
          <div className="card space-y-3">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Регистрация токена' : 'Token registration'}</h3>
                <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Создайте новый API-токен и сохраните его в безопасном месте.' : 'Create a new API token and store it securely.'}</p>
              </div>
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <div className="space-y-1">
                <label className="text-sm text-slate-300">{lang === 'ru' ? 'Метка токена' : 'Token label'}</label>
                <input
                  className="input"
                  value={newTokenLabel}
                  onChange={(e) => setNewTokenLabel(e.target.value)}
                  placeholder={lang === 'ru' ? 'prod-parser-01' : 'prod-parser-01'}
                />
              </div>
              <div className="space-y-1">
                <label className="text-sm text-slate-300">Country</label>
                <select className="input" value={country} onChange={(e) => setCountry(e.target.value)}>
                  <option>US</option>
                  <option>DE</option>
                  <option>RU</option>
                  <option>SG</option>
                </select>
              </div>
            </div>

            <div>
              <button
                className="btn-primary disabled:opacity-60"
                onClick={() => registerTokenMutation.mutate()}
                disabled={registerTokenMutation.isPending || !sessionToken}
              >
                {registerTokenMutation.isPending
                  ? (lang === 'ru' ? 'Регистрация...' : 'Registering...')
                  : (lang === 'ru' ? 'Зарегистрировать токен' : 'Register token')}
              </button>
            </div>

            {registerTokenMutation.isError && (
              <p className="text-red-400">Error: {(registerTokenMutation.error as Error).message}</p>
            )}
            {registerTokenMutation.isSuccess && (
              <div className="rounded-xl border border-emerald-400/40 bg-emerald-500/10 p-4 text-sm text-emerald-100">
                <div className="mb-2 font-semibold">{lang === 'ru' ? 'Токен создан' : 'Token created'}</div>
                <div className="space-y-1">
                  <div className="font-mono">token: {registerTokenMutation.data.token}</div>
                  <div className="font-mono">username: {registerTokenMutation.data.username}</div>
                  <div className="font-mono">proxy: {registerTokenMutation.data.proxy_host}:{registerTokenMutation.data.proxy_port}</div>
                </div>
              </div>
            )}
          </div>

          <div className="card space-y-3">
            <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Зарегистрированные токены' : 'Registered tokens'}</h3>
            {businessTokensQuery.isLoading && <p className="text-slate-400">{lang === 'ru' ? 'Загрузка...' : 'Loading...'}</p>}
            {businessTokensQuery.isError && <p className="text-red-400">Error: {(businessTokensQuery.error as Error).message}</p>}
            {businessTokensQuery.data && businessTokensQuery.data.length === 0 && (
              <p className="text-slate-400">{lang === 'ru' ? 'Пока нет токенов. Зарегистрируйте первый.' : 'No tokens yet. Register your first one.'}</p>
            )}
            {businessTokensQuery.data && businessTokensQuery.data.length > 0 && (
              <div className="overflow-x-auto">
                <table className="table min-w-[680px]">
                  <thead>
                    <tr>
                      <th>{lang === 'ru' ? 'Логин' : 'Username'}</th>
                      <th>{lang === 'ru' ? 'Метка' : 'Label'}</th>
                      <th>{lang === 'ru' ? 'Создан' : 'Created'}</th>
                      <th>{lang === 'ru' ? 'Действие' : 'Action'}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {businessTokensQuery.data.map((tokenItem) => (
                      <tr key={tokenItem.credential_id}>
                        <td className="font-mono text-slate-200">{tokenItem.username}</td>
                        <td className="text-slate-300">{tokenItem.label ?? '—'}</td>
                        <td className="text-slate-400">{new Date(tokenItem.created_at).toLocaleString()}</td>
                        <td>
                          <button
                            className="btn-ghost !px-2 !py-1 !text-xs"
                            onClick={() => revokeTokenMutation.mutate(tokenItem.credential_id)}
                            disabled={revokeTokenMutation.isPending}
                          >
                            {lang === 'ru' ? 'Отозвать' : 'Revoke'}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {activeTab === 'credentials' && (
        <>
          <div className="card space-y-3">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Выдача рабочего доступа' : 'Issue operational credential'}</h3>
                <p className="text-slate-400 text-sm">{lang === 'ru' ? 'Создайте учетные данные с выбором региона.' : 'Create credential with region selection.'}</p>
              </div>
              {!enabled && <span className="text-xs text-slate-500">{lang === 'ru' ? 'Сначала укажите токен' : 'Provide token first'}</span>}
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <div className="space-y-1">
                <label className="text-sm text-slate-300">Метка</label>
                <input
                  className="input"
                  value={newCredLabel}
                  onChange={(e) => setNewCredLabel(e.target.value)}
                  placeholder="crawler-eu-1"
                />
              </div>
              <div className="space-y-1">
                <label className="text-sm text-slate-300">Country</label>
                <select className="input" value={country} onChange={(e) => setCountry(e.target.value)}>
                  <option>US</option>
                  <option>DE</option>
                  <option>RU</option>
                  <option>SG</option>
                </select>
              </div>
            </div>

            <div>
              <button
                className="btn-primary disabled:opacity-60"
                onClick={() => createMutation.mutate({ label: newCredLabel || undefined, country })}
                disabled={createMutation.isPending || !enabled}
              >
                {createMutation.isPending ? (lang === 'ru' ? 'Создание...' : 'Creating...') : (lang === 'ru' ? 'Создать доступ' : 'Create credential')}
              </button>
            </div>

            {createMutation.isError && (
              <p className="text-red-400">Error: {(createMutation.error as Error).message}</p>
            )}
            {createMutation.isSuccess && (
              <div className="rounded-xl border border-emerald-400/40 bg-emerald-500/10 p-4 text-sm text-emerald-100">
                <div className="mb-2 font-semibold">{lang === 'ru' ? 'Доступ выдан' : 'Credential issued'}</div>
                <div className="space-y-1">
                  <div className="font-mono">username: {createMutation.data.username}</div>
                  <div className="font-mono">password: {createMutation.data.password}</div>
                  <div className="font-mono">proxy: {createMutation.data.proxy_host}:{createMutation.data.proxy_port}</div>
                </div>
              </div>
            )}
          </div>

          <div className="card space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Выданные доступы' : 'Issued credentials'}</h3>
            </div>
            {credentialsQuery.isLoading && <p className="text-slate-400">{lang === 'ru' ? 'Загрузка...' : 'Loading...'}</p>}
            {credentialsQuery.isError && <p className="text-red-400">Error: {(credentialsQuery.error as Error).message}</p>}
            {credentialsQuery.data && credentialsQuery.data.length === 0 && (
              <p className="text-slate-400">{lang === 'ru' ? 'Пока нет выданных доступов. Создайте первый.' : 'No credentials yet. Create your first one.'}</p>
            )}
            {credentialsQuery.data && credentialsQuery.data.length > 0 && (
              <div className="overflow-x-auto">
                <table className="table min-w-[640px]">
                  <thead>
                    <tr>
                      <th>{lang === 'ru' ? 'Логин' : 'Username'}</th>
                      <th>{lang === 'ru' ? 'Метка' : 'Label'}</th>
                      <th>{lang === 'ru' ? 'Создан' : 'Created'}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {credentialsQuery.data.map((c) => (
                      <tr key={c.credential_id}>
                        <td className="font-mono text-slate-200">{c.username}</td>
                        <td className="text-slate-300">{c.label ?? '—'}</td>
                        <td className="text-slate-400">{new Date(c.created_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {activeTab === 'billing' && (
        <div className="grid gap-4 md:grid-cols-2">
          <div className="card space-y-3">
            <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Баланс и лимиты' : 'Balance and limits'}</h3>
            {balanceQuery.isLoading && <p className="text-slate-400">{lang === 'ru' ? 'Загрузка...' : 'Loading...'}</p>}
            {balanceQuery.isError && <p className="text-red-400">Error: {(balanceQuery.error as Error).message}</p>}
            {balanceQuery.data && (
              <>
                <p className="text-4xl font-bold text-white">${balanceQuery.data.balance_usd.toFixed(2)}</p>
                <p className="text-slate-400 text-sm">client_id: {balanceQuery.data.client_id}</p>
              </>
            )}
            <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4 text-sm text-slate-300">
              {lang === 'ru'
                ? 'Рекомендуем настроить автоматическое оповещение о низком балансе (например, при остатке < $20).'
                : 'Recommended: set automated low-balance alerts (for example, when balance < $20).'}
            </div>
          </div>

          <div className="card space-y-3">
            <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Как организовать прием платежей' : 'How to organize payment acceptance'}</h3>
            <div className="space-y-3 text-sm text-slate-300">
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4">
                <p className="font-semibold text-white">{lang === 'ru' ? '1. Ручные пополнения (сейчас)' : '1. Manual top-ups (now)'}</p>
                <p className="mt-1">{lang === 'ru' ? 'Принимайте переводы по реквизитам и пополняйте баланс клиента через админку.' : 'Accept bank transfers and top up client balances from the admin panel.'}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4">
                <p className="font-semibold text-white">{lang === 'ru' ? '2. Merchant of Record (посредник)' : '2. Merchant of Record'}</p>
                <p className="mt-1">{lang === 'ru' ? 'Используйте Paddle/Lemon Squeezy/Gumroad как юридического продавца и получателя карт.' : 'Use Paddle/Lemon Squeezy/Gumroad as legal seller of record and card processor.'}</p>
              </div>
              <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-4">
                <p className="font-semibold text-white">{lang === 'ru' ? '3. Позже подключить эквайринг' : '3. Add direct acquiring later'}</p>
                <p className="mt-1">{lang === 'ru' ? 'Когда будет оформлен юр-статус, подключить Stripe/Т-Банк/ЮKassa напрямую.' : 'Once legal status is ready, connect Stripe/local acquirers directly.'}</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
