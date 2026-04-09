import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';

export default function ClientHome() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const cards = lang === 'ru'
    ? [
        { title: 'Просто включить', text: 'Один тап - и можно пользоваться интернетом как обычно.' },
        { title: 'Комфортно каждый день', text: 'Приложение сделано для повседневного использования без лишних настроек.' },
        { title: 'Понятный интерфейс', text: 'Только нужные кнопки и статусы, без перегруженных экранов.' }
      ]
    : [
        { title: 'Easy to start', text: 'One tap to connect, then you use the internet normally.' },
        { title: 'Comfortable daily use', text: 'Built for day-to-day use without constant tweaking.' },
        { title: 'Clear interface', text: 'Only the essentials, with simple status feedback.' }
      ];

  return (
    <div className="space-y-10">
      <section className="relative overflow-hidden rounded-3xl border border-slate-800/70 bg-panel/70 p-8 md:p-12">
        <div className="absolute -right-10 top-0 h-40 w-40 rounded-full bg-cyan-300/15 blur-3xl" />
        <div className="absolute bottom-0 left-0 h-40 w-40 rounded-full bg-emerald-300/10 blur-3xl" />
        <div className="relative space-y-6">
          <div className="badge">ByteAway Android</div>
          <h1 className="max-w-4xl text-4xl font-bold leading-tight text-white md:text-5xl">
            {lang === 'ru'
              ? 'Приватный VPN для Android без сложностей'
              : 'Private Android VPN made simple'}
          </h1>
          <p className="max-w-3xl text-lg text-slate-300">
            {lang === 'ru'
              ? 'Подключайтесь за пару секунд и работайте спокойно: без технической перегрузки и лишних объяснений.'
              : 'Connect in seconds and keep going with a clean, no-nonsense experience.'}
          </p>
          <div className="flex flex-wrap gap-3">
            <Link to={withLocale(lang, '/client/download')} className="btn-primary">{lang === 'ru' ? 'Скачать APK' : 'Download APK'}</Link>
            <Link to={withLocale(lang, '/client/how-it-works')} className="btn-ghost">{lang === 'ru' ? 'Как начать' : 'Getting started'}</Link>
          </div>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        {cards.map((item) => (
          <article key={item.title} className="card space-y-2">
            <h2 className="text-lg font-semibold text-white">{item.title}</h2>
            <p className="text-slate-300 leading-relaxed">{item.text}</p>
          </article>
        ))}
      </section>
    </div>
  );
}
