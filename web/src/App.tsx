import { useEffect, useState, useRef } from 'react';
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

function GlobalHeader({ type, lang, authorized, logout }: { type: 'client' | 'business', lang: string, authorized?: boolean, logout?: () => void }) {
  const { pathname } = useLocation();
  const [visible, setVisible] = useState(true);
  const [scrolled, setScrolled] = useState(false);
  const lastScrollY = useRef(0);
  const otherLang = lang === 'ru' ? 'en' : 'ru';
  const active = (path: string) => pathname === path;

  useEffect(() => {
    const handleScroll = () => {
      const currentScrollY = window.scrollY;
      setScrolled(currentScrollY > 20);

      if (currentScrollY > lastScrollY.current && currentScrollY > 120) {
        setVisible(false);
      } else {
        setVisible(true);
      }
      lastScrollY.current = currentScrollY;
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <header className={`fixed top-0 left-0 right-0 z-[100] transition-all duration-500 ease-in-out transform ${visible ? 'translate-y-0' : '-translate-y-full'} ${scrolled ? 'bg-ink/95 backdrop-blur-2xl border-b border-white/10 py-3 shadow-2xl' : 'bg-transparent py-7'}`}>
      <div className="mx-auto flex w-full max-w-6xl items-center justify-between px-6">
        <Link to={withLocale(lang, type === 'client' ? '/client' : '/business')} className="flex items-center gap-3 group">
          <img src="/logo.png" alt="ByteAway" className="h-8 w-8 rounded-lg shadow-lg shadow-blue-600/20 group-hover:scale-110 transition-transform" />
          <span className="text-xl font-display font-bold text-white tracking-tight">ByteAway</span>
          {type === 'business' && <span className="text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black ml-1">B2B</span>}
        </Link>

        <nav className="hidden items-center gap-1 text-sm font-semibold md:flex">
          {type === 'client' ? (
            <>
              <NavLink to={withLocale(lang, '/client')} active={active(withLocale(lang, '/client'))}>{lang === 'ru' ? 'Главная' : 'Home'}</NavLink>
              <NavLink to={withLocale(lang, '/client/how-it-works')} active={active(withLocale(lang, '/client/how-it-works'))}>{lang === 'ru' ? 'Как это работает' : 'How it works'}</NavLink>
              <NavLink to={withLocale(lang, '/client/download')} active={active(withLocale(lang, '/client/download'))}>{lang === 'ru' ? 'Загрузки' : 'Downloads'}</NavLink>
            </>
          ) : (
            <>
              <NavLink to={withLocale(lang, '/business')} active={active(withLocale(lang, '/business'))}>{lang === 'ru' ? 'Платформа' : 'Platform'}</NavLink>
              {authorized && <NavLink to={withLocale(lang, '/business/console')} active={active(withLocale(lang, '/business/console'))}>{lang === 'ru' ? 'Консоль' : 'Console'}</NavLink>}
            </>
          )}
          
          <div className="w-px h-5 bg-white/10 mx-5" />
          
          {type === 'business' && !authorized && (
            <Link to={withLocale(lang, '/business/login')} className="text-slate-400 hover:text-white px-3 py-2 transition-colors">
              {lang === 'ru' ? 'Вход' : 'Login'}
            </Link>
          )}

          {authorized && logout ? (
            <button onClick={logout} className="text-slate-400 hover:text-red-400 px-3 py-2 transition-colors">
              {lang === 'ru' ? 'Выйти' : 'Logout'}
            </button>
          ) : (
             <Link 
               to={withLocale(lang, type === 'client' ? '/business' : '/client')} 
               className="btn-primary !py-2.5 !px-6 !text-xs ml-2 shadow-xl shadow-white/5"
             >
              {type === 'client' 
                ? (lang === 'ru' ? 'Для бизнеса' : 'For Business')
                : (lang === 'ru' ? 'Для частных лиц' : 'For Clients')
              }
            </Link>
          )}
          
          <Link to={switchLocalePath(pathname, otherLang)} className="ml-4 w-10 h-10 flex items-center justify-center rounded-xl border border-white/10 text-[10px] font-black text-slate-500 hover:text-white hover:border-white/20 transition-all uppercase">
            {lang === 'ru' ? 'en' : 'ru'}
          </Link>
        </nav>
      </div>
    </header>
  );
}

function NavLink({ to, children, active }: { to: string, children: React.ReactNode, active: boolean }) {
  return (
    <Link to={to} className={`px-4 py-2 rounded-xl transition-all ${active ? 'text-white bg-white/5 shadow-inner' : 'text-slate-500 hover:text-slate-200'}`}>
      {children}
    </Link>
  );
}

function GiantFooter({ lang }: { lang: string }) {
  return (
    <footer className="relative mt-48 pb-0 border-t border-white/5 overflow-hidden bg-gradient-to-b from-transparent to-black/30">
      <div className="mx-auto max-w-6xl px-6 grid grid-cols-1 md:grid-cols-4 gap-20 py-24">
        <div className="col-span-1 md:col-span-2 space-y-10">
          <div className="flex items-center gap-4">
            <img src="/logo.png" className="h-12 w-12 rounded-2xl shadow-2xl" />
            <span className="font-display font-bold text-4xl tracking-tighter">ByteAway</span>
          </div>
          <p className="text-slate-500 max-w-sm text-xl leading-relaxed font-medium">
            {lang === 'ru' 
              ? 'Глобальная сеть доступа, построенная на принципах прозрачности.' 
              : 'Global access network built on transparency principles.'}
          </p>
        </div>
        <div className="space-y-10">
           <h4 className="text-xs uppercase tracking-[0.5em] font-black text-white/20">{lang === 'ru' ? 'Ресурсы' : 'Resources'}</h4>
           <nav className="flex flex-col gap-5 text-base font-medium text-slate-400">
             <Link to={withLocale(lang, '/client/download')} className="hover:text-white transition-colors">{lang === 'ru' ? 'Скачать' : 'Download'}</Link>
             <Link to={withLocale(lang, '/client/how-it-works')} className="hover:text-white transition-colors">{lang === 'ru' ? 'Как это работает' : 'How it works'}</Link>
             <Link to={withLocale(lang, '/business')} className="hover:text-white transition-colors">{lang === 'ru' ? 'Бизнес' : 'Business'}</Link>
           </nav>
        </div>
        <div className="space-y-10">
           <h4 className="text-xs uppercase tracking-[0.5em] font-black text-white/20">{lang === 'ru' ? 'Право' : 'Legal'}</h4>
           <nav className="flex flex-col gap-5 text-base font-medium text-slate-400">
             <Link to={withLocale(lang, '/client/privacy')} className="hover:text-white transition-colors">{lang === 'ru' ? 'Приватность' : 'Privacy'}</Link>
             <Link to={withLocale(lang, '/client/terms')} className="hover:text-white transition-colors">{lang === 'ru' ? 'Условия' : 'Terms'}</Link>
           </nav>
        </div>
      </div>

      <div className="mx-auto max-w-6xl px-6 py-12 flex flex-col md:flex-row justify-between items-center text-[10px] font-black tracking-[0.3em] text-slate-700 gap-8 border-t border-white/5">
        <span className="uppercase">© 2026 BYTEAWAY NETWORK</span>
        <span className="uppercase opacity-40">POWERED BY OSPAB.NETWORK</span>
      </div>

      <div className="relative select-none pointer-events-none mt-10 flex justify-center items-end leading-none">
        <h2 className="text-[14vw] font-display font-black text-white/[0.02] tracking-[-0.04em] whitespace-nowrap text-center transition-all duration-1000 hover:text-white/[0.07] pb-8">
          BYTEAWAY
        </h2>
      </div>
    </footer>
  );
}

function ClientLayout() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  return (
    <div className="min-h-screen flex flex-col selection:bg-accent/30 pt-32">
      <GlobalHeader type="client" lang={lang} />
      <div className="flex-1">
        <main className="mx-auto w-full max-w-6xl px-6 py-16">
          <Outlet />
        </main>
      </div>
      <GiantFooter lang={lang} />
    </div>
  );
}

function BusinessLayout() {
  const navigate = useNavigate();
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const authorized = isBusinessAuthorized();

  const logout = () => {
    localStorage.removeItem(BUSINESS_SESSION_KEY);
    localStorage.removeItem(BUSINESS_SESSION_TOKEN_KEY);
    navigate(withLocale(lang, '/business/login'));
  };

  return (
    <div className="min-h-screen flex flex-col selection:bg-accent2/30 bg-[#060a14] pt-32">
      <GlobalHeader type="business" lang={lang} authorized={authorized} logout={logout} />
      <div className="flex-1">
        <main className="mx-auto w-full max-w-6xl px-6 py-16">
          <Outlet />
        </main>
      </div>
      <GiantFooter lang={lang} />
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
