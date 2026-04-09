import { Link, useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../i18n';

export default function NotFound() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  return (
    <div className="mx-auto flex min-h-[60vh] w-full max-w-3xl items-center justify-center px-4">
      <div className="card w-full text-center">
        <p className="text-sm uppercase tracking-widest text-slate-500">{lang === 'ru' ? 'Ошибка маршрута' : 'Routing error'}</p>
        <h1 className="mt-3 text-5xl font-bold text-white">404</h1>
        <p className="mt-3 text-slate-300">{lang === 'ru' ? 'Страница не найдена или была перемещена.' : 'The page was not found or has been moved.'}</p>
        <div className="mt-6">
          <Link to={withLocale('/client', lang)} className="btn-primary">
            {lang === 'ru' ? 'Вернуться на главную' : 'Back to home'}
          </Link>
        </div>
      </div>
    </div>
  );
}
