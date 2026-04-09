import { useEffect, useState } from 'react';
import { Routes, Route, Navigate, Link, Outlet, useLocation, useNavigate, useParams } from 'react-router-dom';
import ClientHome from './pages/client/ClientHome';
import ClientDownload from './pages/client/ClientDownload';
import ClientHow from './pages/client/ClientHow';
import PrivacyPolicy from './pages/client/PrivacyPolicy';
import TermsOfUse from './pages/client/TermsOfUse';
import BusinessHome from './pages/business/BusinessHome';
import BusinessDashboard from './pages/business/BusinessDashboard';
import BusinessLogin from './pages/business/BusinessLogin';
import BusinessRegister from './pages/business/BusinessRegister';
import NotFound from './pages/NotFound';
import { normalizeLocale, switchLocalePath, withLocale } from './i18n';

const BUSINESS_SESSION_KEY = 'byteaway_business_session';
const BUSINESS_SESSION_TOKEN_KEY = 'byteaway_business_session_token';

function isBusinessAuthorized() {
  return localStorage.getItem(BUSINESS_SESSION_KEY) === '1' && !!localStorage.getItem(BUSINESS_SESSION_TOKEN_KEY);
}

function RequireBusinessAuth({ children }: { children: JSX.Element }) {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  if (!isBusinessAuthorized()) {
    return <Navigate to={withLocale(lang, '/business/login')} replace />;
  }
  return children;
}

function ClientLayout() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const { pathname } = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const otherLang = lang === 'ru' ? 'en' : 'ru';
  const languageLabel = lang === 'ru' ? 'EN' : 'RU';
  const active = (path: string) => (pathname === path ? 'bg-slate-800/60 border border-slate-700' : '');

  useEffect(() => {
    setMobileNavOpen(false);
  }, [pathname]);

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-slate-800/60 bg-panel/70 backdrop-blur">
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between px-4 py-4">
          <Link to={withLocale(lang, '/client')} className="text-xl font-bold text-white">ByteAway</Link>

          <button
            type="button"
            className="btn-ghost !px-3 !py-2 !text-sm md:hidden"
            onClick={() => setMobileNavOpen((v) => !v)}
            aria-expanded={mobileNavOpen}
            aria-label={lang === 'ru' ? 'Открыть меню' : 'Open menu'}
          >
            {mobileNavOpen ? (lang === 'ru' ? 'Закрыть' : 'Close') : 'Menu'}
          </button>

          <nav className="hidden items-center gap-2 text-sm md:flex">
            <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client'))}`} to={withLocale(lang, '/client')}>
              {lang === 'ru' ? 'Главная' : 'Home'}
            </Link>
            <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client/how-it-works'))}`} to={withLocale(lang, '/client/how-it-works')}>
              {lang === 'ru' ? 'Как начать' : 'Getting started'}
            </Link>
            <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client/download'))}`} to={withLocale(lang, '/client/download')}>
              {lang === 'ru' ? 'Скачать' : 'Download'}
            </Link>
            <Link className="btn-primary !px-3 !py-2 !text-sm" to={withLocale(lang, '/client/download')}>
              {lang === 'ru' ? 'Скачать APK' : 'Download APK'}
            </Link>
            <Link className="btn-ghost !px-3 !py-2 !text-sm" to={switchLocalePath(pathname, otherLang)}>{languageLabel}</Link>
          </nav>
        </div>

        {mobileNavOpen && (
          <div className="border-t border-slate-800/60 px-4 pb-4 md:hidden">
            <nav className="flex flex-col gap-2 pt-3 text-sm">
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client'))}`} to={withLocale(lang, '/client')}>
                {lang === 'ru' ? 'Главная' : 'Home'}
              </Link>
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client/how-it-works'))}`} to={withLocale(lang, '/client/how-it-works')}>
                {lang === 'ru' ? 'Как начать' : 'Getting started'}
              </Link>
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/client/download'))}`} to={withLocale(lang, '/client/download')}>
                {lang === 'ru' ? 'Скачать' : 'Download'}
              </Link>
              <Link className="btn-primary !px-3 !py-2 !text-sm" to={withLocale(lang, '/client/download')}>
                {lang === 'ru' ? 'Скачать APK' : 'Download APK'}
              </Link>
              <Link className="btn-ghost !px-3 !py-2 !text-sm" to={switchLocalePath(pathname, otherLang)}>{languageLabel}</Link>
            </nav>
          </div>
        )}
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-10">
        <Outlet />
      </main>
      <footer className="border-t border-slate-800/60 bg-panel/50">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-3 px-4 py-6 text-sm text-slate-400 md:flex-row md:items-center md:justify-between">
          <p>{lang === 'ru' ? '© 2026 ByteAway. Все права защищены.' : '© 2026 ByteAway. All rights reserved.'}</p>
          <div className="flex items-center gap-4">
            <Link className="hover:text-slate-200" to={withLocale(lang, '/client/privacy')}>
              {lang === 'ru' ? 'Политика конфиденциальности' : 'Privacy policy'}
            </Link>
            <Link className="hover:text-slate-200" to={withLocale(lang, '/client/terms')}>
              {lang === 'ru' ? 'Условия пользования' : 'Terms of use'}
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}

function BusinessLayout() {
  const navigate = useNavigate();
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const { pathname } = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const otherLang = lang === 'ru' ? 'en' : 'ru';
  const languageLabel = lang === 'ru' ? 'EN' : 'RU';
  const active = (path: string) => (pathname === path ? 'bg-slate-800/60 border border-slate-700' : '');
  const authorized = isBusinessAuthorized();

  useEffect(() => {
    setMobileNavOpen(false);
  }, [pathname]);

  const logout = () => {
    localStorage.removeItem(BUSINESS_SESSION_KEY);
    localStorage.removeItem(BUSINESS_SESSION_TOKEN_KEY);
    navigate(withLocale(lang, '/business/login'));
  };

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-slate-800/60 bg-panel/70 backdrop-blur">
        <div className="mx-auto flex w-full max-w-5xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 rounded-xl bg-gradient-to-r from-accent to-accent2" />
            <div>
              <div className="text-sm uppercase tracking-widest text-slate-400">B2B Console</div>
              <div className="text-lg font-semibold text-white">ByteAway</div>
            </div>
          </div>
          <button
            type="button"
            className="btn-ghost !px-3 !py-2 !text-sm md:hidden"
            onClick={() => setMobileNavOpen((v) => !v)}
            aria-expanded={mobileNavOpen}
            aria-label={lang === 'ru' ? 'Открыть меню' : 'Open menu'}
          >
            {mobileNavOpen ? (lang === 'ru' ? 'Закрыть' : 'Close') : 'Menu'}
          </button>

          <nav className="hidden items-center gap-2 text-sm md:flex">
            <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business'))}`} to={withLocale(lang, '/business')}>
              {lang === 'ru' ? 'Платформа' : 'Platform'}
            </Link>
            {authorized && (
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/console'))}`} to={withLocale(lang, '/business/console')}>
                {lang === 'ru' ? 'Кабинет' : 'Console'}
              </Link>
            )}
            {!authorized && (
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/login'))}`} to={withLocale(lang, '/business/login')}>
                {lang === 'ru' ? 'Вход' : 'Login'}
              </Link>
            )}
            {!authorized && (
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/register'))}`} to={withLocale(lang, '/business/register')}>
                {lang === 'ru' ? 'Регистрация' : 'Register'}
              </Link>
            )}
            {authorized && (
              <button className="btn-ghost !px-3 !py-2 !text-sm" onClick={logout}>
                {lang === 'ru' ? 'Выход' : 'Logout'}
              </button>
            )}
            <Link className="btn-primary !px-3 !py-2 !text-sm" to={withLocale(lang, '/client/download')}>
              {lang === 'ru' ? 'Скачать APK' : 'Download APK'}
            </Link>
            <Link className="btn-ghost !px-3 !py-2 !text-sm" to={switchLocalePath(pathname, otherLang)}>{languageLabel}</Link>
          </nav>
        </div>

        {mobileNavOpen && (
          <div className="border-t border-slate-800/60 px-4 pb-4 md:hidden">
            <nav className="flex flex-col gap-2 pt-3 text-sm">
              <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business'))}`} to={withLocale(lang, '/business')}>
                {lang === 'ru' ? 'Платформа' : 'Platform'}
              </Link>
              {authorized && (
                <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/console'))}`} to={withLocale(lang, '/business/console')}>
                  {lang === 'ru' ? 'Кабинет' : 'Console'}
                </Link>
              )}
              {!authorized && (
                <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/login'))}`} to={withLocale(lang, '/business/login')}>
                  {lang === 'ru' ? 'Вход' : 'Login'}
                </Link>
              )}
              {!authorized && (
                <Link className={`px-3 py-2 rounded-lg text-slate-100 ${active(withLocale(lang, '/business/register'))}`} to={withLocale(lang, '/business/register')}>
                  {lang === 'ru' ? 'Регистрация' : 'Register'}
                </Link>
              )}
              {authorized && (
                <button className="btn-ghost !px-3 !py-2 !text-sm justify-start" onClick={logout}>
                  {lang === 'ru' ? 'Выход' : 'Logout'}
                </button>
              )}
              <Link className="btn-primary !px-3 !py-2 !text-sm" to={withLocale(lang, '/client/download')}>
                {lang === 'ru' ? 'Скачать APK' : 'Download APK'}
              </Link>
              <Link className="btn-ghost !px-3 !py-2 !text-sm" to={switchLocalePath(pathname, otherLang)}>{languageLabel}</Link>
            </nav>
          </div>
        )}
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-10">
        <Outlet />
      </main>
      <footer className="border-t border-slate-800/60 bg-panel/50">
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-3 px-4 py-6 text-sm text-slate-400 md:flex-row md:items-center md:justify-between">
          <p>© 2026 ByteAway B2B. Built and maintained by ospab.</p>
          <div className="flex items-center gap-4">
            <Link className="hover:text-slate-200" to={withLocale(lang, '/client/privacy')}>Privacy</Link>
            <Link className="hover:text-slate-200" to={withLocale(lang, '/client/terms')}>Terms</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/ru/client" replace />} />

      <Route path=":locale/client" element={<ClientLayout />}>
        <Route index element={<ClientHome />} />
        <Route path="how-it-works" element={<ClientHow />} />
        <Route path="download" element={<ClientDownload />} />
        <Route path="privacy" element={<PrivacyPolicy />} />
        <Route path="terms" element={<TermsOfUse />} />
      </Route>

      <Route path=":locale/business" element={<BusinessLayout />}>
        <Route index element={<BusinessHome />} />
        <Route path="login" element={<BusinessLogin />} />
        <Route path="register" element={<BusinessRegister />} />
        <Route path="console" element={<RequireBusinessAuth><BusinessDashboard /></RequireBusinessAuth>} />
      </Route>

      <Route path="client/*" element={<Navigate to="/ru/client" replace />} />
      <Route path="business/*" element={<Navigate to="/ru/business" replace />} />

      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
