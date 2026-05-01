import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';

export default function ClientHome() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const t = {
    badge: 'ByteAway Personal',
    title: lang === 'ru' 
      ? 'Интернет без границ и компромиссов'
      : 'Internet without boundaries',
    lead: lang === 'ru'
      ? 'Забудьте про блокировки и сложные настройки. Получите премиальный доступ бесплатно, делясь ресурсами с нашими бизнес-партнерами.'
      : 'Forget about blocks and complex setups. Get premium access for free by sharing resources with our business partners.',
    download: lang === 'ru' ? 'Скачать APK' : 'Download APK',
    guide: lang === 'ru' ? 'Как это работает?' : 'How it works?',
    benefits: lang === 'ru' ? [
      { title: 'В одно касание', text: 'Никаких списков серверов и протоколов. Одна кнопка — и вы свободны.' },
      { title: 'Честный обмен', text: 'Доступ бесплатен, пока вы помогаете верифицированным компаниям в их работе.' },
      { title: 'Полная приватность', text: 'Мы не знаем, кто вы и что делаете. Ваши данные защищены по умолчанию.' }
    ] : [
      { title: 'One Tap', text: 'No server lists or protocols. One button — and you are free.' },
      { title: 'Fair Exchange', text: 'Access is free while you help verified companies with their operations.' },
      { title: 'Full Privacy', text: 'We don\'t know who you are or what you do. Your data is secure by default.' }
    ]
  };

  return (
    <div className="space-y-32 pb-20">
      {/* Hero */}
      <section className="flex flex-col md:flex-row items-center gap-12 pt-10">
        <div className="flex-1 space-y-8">
          <span className="badge">{t.badge}</span>
          <h1 className="text-5xl md:text-7xl font-display font-bold leading-tight text-white">
            {t.title}
          </h1>
          <p className="text-xl text-slate-400 leading-relaxed max-w-xl">
            {t.lead}
          </p>
          <div className="flex flex-wrap gap-4">
            <Link to={withLocale(lang, '/client/download')} className="btn-primary px-8">
              {t.download}
            </Link>
            <Link to={withLocale(lang, '/client/how-it-works')} className="btn-ghost px-8">
              {t.guide}
            </Link>
          </div>
        </div>

        <div className="flex-1 relative">
          <div className="w-64 h-[500px] mx-auto bg-slate-900 rounded-[3rem] border-[8px] border-slate-800 shadow-2xl relative overflow-hidden">
             {/* Mock UI */}
             <div className="absolute top-0 w-full h-6 flex justify-center items-center">
                <div className="w-16 h-1 bg-slate-800 rounded-full" />
             </div>
             <div className="p-6 pt-12 space-y-6">
                <div className="h-4 w-24 bg-white/5 rounded" />
                <div className="h-32 w-full bg-gradient-to-br from-accent/20 to-accent2/20 rounded-2xl border border-white/5 flex items-center justify-center">
                   <div className="h-12 w-12 rounded-full bg-white flex items-center justify-center shadow-lg">
                      <div className="h-4 w-4 bg-ink rounded-sm rotate-45" />
                   </div>
                </div>
                <div className="space-y-3">
                   <div className="h-3 w-full bg-white/5 rounded" />
                   <div className="h-3 w-2/3 bg-white/5 rounded" />
                </div>
                <div className="pt-20">
                   <div className="h-12 w-full bg-white/10 rounded-xl" />
                </div>
             </div>
          </div>
          {/* Decorative Glows */}
          <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-80 h-80 bg-accent/20 blur-[100px] -z-10 rounded-full" />
        </div>
      </section>

      {/* Benefits */}
      <section className="grid gap-6 md:grid-cols-3">
        {t.benefits.map((b) => (
          <div key={b.title} className="card">
            <h3 className="text-lg font-bold text-white mb-2">{b.title}</h3>
            <p className="text-slate-400 text-sm leading-relaxed">{b.text}</p>
          </div>
        ))}
      </section>

      {/* OS Support */}
      <section className="text-center space-y-8 py-10 border-t border-white/5">
         <p className="text-[10px] uppercase tracking-[0.4em] text-slate-500 font-bold">Supported Platforms</p>
         <div className="flex justify-center items-center gap-12 opacity-50 grayscale hover:grayscale-0 transition-all">
            <span className="text-2xl font-bold flex items-center gap-2">
               <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24"><path d="M17.523 15.3414C17.523 15.3414 17.523 15.3414 17.523 15.3414C17.523 15.3414 17.523 15.3414 17.523 15.3414ZM17.523 15.3414L17.523 15.3414Z"></path><path d="M17.523 15.3414C15.935 18.0674 13.067 19.9234 9.761 19.9234C5.033 19.9234 1.201 16.0914 1.201 11.3634C1.201 6.6354 5.033 2.8034 9.761 2.8034C13.067 2.8034 15.935 4.6594 17.523 7.3854L19.761 6.0914C17.761 2.6284 14.041 0.3034 9.761 0.3034C3.653 0.3034 -1.299 5.2554 -1.299 11.3634C -1.299 17.4714 3.653 22.4234 9.761 22.4234C14.041 22.4234 17.761 20.0984 19.761 16.6354L17.523 15.3414Z"></path></svg>
               Android
            </span>
            <span className="text-2xl font-bold opacity-30">iOS (Coming Soon)</span>
            <span className="text-2xl font-bold opacity-30">Windows (Beta)</span>
         </div>
      </section>
    </div>
  );
}
