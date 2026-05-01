import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';

export default function BusinessHome() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const t = {
    badge: lang === 'ru' ? 'ByteAway для бизнеса' : 'ByteAway for Business',
    title: lang === 'ru'
      ? 'Управляемый доступ и сетевая безопасность для бизнеса'
      : 'Managed Access & Network Security for Enterprise',
    lead: lang === 'ru'
      ? 'Профессиональная инфраструктура для тех, кому важен контроль. Полный аудит, гибкие роли и стабильные каналы связи для ваших рабочих задач.'
      : 'Professional infrastructure for those who value control. Full auditing, flexible roles, and stable connectivity for your operational needs.',
    login: lang === 'ru' ? 'Вход в консоль' : 'Console Login',
    register: lang === 'ru' ? 'Регистрация компании' : 'Register Account',
    pillars: lang === 'ru' ? [
      { title: 'Прозрачный аудит', text: 'Вы всегда знаете, кто, когда и зачем использовал доступ. Никаких «серых зон» в логах.' },
      { title: 'Точечные права', text: 'Выдавайте доступы именно тем командам, которым они нужны. Включайте и отключайте в один клик.' },
      { title: 'Железный SLA', text: 'Наши узлы работают стабильно в ключевых регионах. Ваша работа не должна зависеть от перебоев.' }
    ] : [
      { title: 'Transparent Audit', text: 'Always know who, when, and why access was used. No "grey areas" in your logs.' },
      { title: 'Granular Access', text: 'Issue credentials exactly to the teams that need them. Enable or disable with a single click.' },
      { title: 'Solid SLA', text: 'Our nodes stay stable in key regions. Your operations shouldn\'t depend on network downtime.' }
    ],
    steps: lang === 'ru' ? [
      { step: '01', title: 'Регистрация', text: 'Создайте корпоративный профиль и верифицируйте данные.' },
      { step: '02', title: 'Настройка', text: 'Определите параметры доступа и ключи для ваших команд.' },
      { step: '03', title: 'Операции', text: 'Управляйте доступом и отчетами через единую консоль.' }
    ] : [
      { step: '01', title: 'Registration', text: 'Create a corporate profile and verify your business details.' },
      { step: '02', title: 'Configuration', text: 'Define access parameters and keys for your teams.' },
      { step: '03', title: 'Operations', text: 'Manage access and reports via a unified console.' }
    ]
  };

  return (
    <div className="space-y-32 pb-20">
      {/* Hero Section */}
      <section className="relative pt-12">
        <div className="absolute -top-24 left-1/2 -translate-x-1/2 w-full max-w-4xl h-96 bg-accent/10 blur-[120px] rounded-full pointer-events-none" />
        
        <div className="relative text-center space-y-8">
          <div className="flex justify-center">
            <span className="badge">{t.badge}</span>
          </div>
          <h1 className="max-w-4xl mx-auto text-4xl md:text-6xl font-display font-bold leading-[1.1] text-white">
            {t.title}
          </h1>
          <p className="max-w-2xl mx-auto text-lg text-slate-400 leading-relaxed">
            {t.lead}
          </p>
          <div className="flex flex-wrap justify-center gap-4 pt-4">
            <Link to={withLocale(lang, '/business/login')} className="btn-primary min-w-[180px] shadow-2xl shadow-white/10">
              {t.login}
            </Link>
            <Link to={withLocale(lang, '/business/register')} className="btn-ghost min-w-[180px]">
              {t.register}
            </Link>
          </div>
        </div>
      </section>

      {/* Pillars */}
      <section className="grid gap-6 md:grid-cols-3">
        {t.pillars.map((item) => (
          <article key={item.title} className="card group">
            <div className="h-10 w-10 rounded-xl bg-white/5 border border-white/5 flex items-center justify-center mb-6 group-hover:border-accent/30 transition-colors">
              <div className="h-2 w-2 rounded-full bg-accent animate-pulse" />
            </div>
            <h2 className="text-xl font-bold text-white mb-3">{item.title}</h2>
            <p className="text-slate-400 text-sm leading-relaxed">{item.text}</p>
          </article>
        ))}
      </section>

      {/* Steps Section */}
      <section className="space-y-12">
        <div className="text-center space-y-4">
          <h2 className="text-3xl font-bold">{lang === 'ru' ? 'Процесс подключения' : 'Onboarding Process'}</h2>
          <p className="text-slate-500">{lang === 'ru' ? 'Три простых шага до запуска вашей сети' : 'Three simple steps to launch your network'}</p>
        </div>
        
        <div className="grid gap-8 md:grid-cols-3">
          {t.steps.map((s) => (
            <div key={s.step} className="relative group">
              <div className="text-[120px] font-display font-black text-white/[0.03] absolute -top-16 left-0 select-none group-hover:text-accent/[0.05] transition-colors">
                {s.step}
              </div>
              <div className="relative pt-4 space-y-3">
                <h3 className="text-lg font-bold text-white">{s.title}</h3>
                <p className="text-sm text-slate-400 leading-relaxed">{s.text}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Trust Quote */}
      <section className="glass-panel p-10 text-center relative overflow-hidden">
        <div className="absolute top-0 right-0 p-10 opacity-10">
          <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
            <circle cx="50" cy="50" r="48" stroke="currentColor" strokeWidth="4" strokeDasharray="10 10"/>
          </svg>
        </div>
        <p className="text-2xl md:text-3xl font-display font-medium text-slate-200 max-w-3xl mx-auto italic leading-relaxed">
          {lang === 'ru' 
            ? '«Мы создаем инструменты, которым доверяем сами. Приватность — это не опция, это фундамент ByteAway.»'
            : '"We build the tools we trust ourselves. Privacy is not an option, it is the foundation of ByteAway."'}
        </p>
        <div className="mt-8 flex items-center justify-center gap-3">
          <div className="h-px w-8 bg-white/10" />
          <span className="text-[10px] uppercase tracking-[0.4em] text-slate-500 font-bold">ospab dev team</span>
          <div className="h-px w-8 bg-white/10" />
        </div>
      </section>
    </div>
  );
}
