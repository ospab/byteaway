import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';

export default function ClientHow() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const steps = lang === 'ru'
    ? [
        {
          title: '1. Установите приложение',
          text: 'Скачайте APK с сайта и установите его на устройство.'
        },
        {
          title: '2. Нажмите "Подключить"',
          text: 'После запуска просто нажмите кнопку подключения.'
        },
        {
          title: '3. Пользуйтесь как обычно',
          text: 'Откройте нужные сайты и приложения, дальше все работает в фоне.'
        }
      ]
    : [
        {
          title: '1. Install the app',
          text: 'Download the APK from the website and install it on your device.'
        },
        {
          title: '2. Tap "Connect"',
          text: 'Open the app and press connect. That is it.'
        },
        {
          title: '3. Use it normally',
          text: 'Continue browsing and using apps while protection stays active.'
        }
      ];

  return (
    <div className="space-y-8">
      <div className="space-y-3">
        <h1 className="text-3xl font-bold text-white">{lang === 'ru' ? 'Как начать' : 'Getting started'}</h1>
        <p className="text-slate-300 max-w-3xl">
          {lang === 'ru'
            ? 'Три простых шага, чтобы начать пользоваться приложением. Модель сервиса: бесплатный доступ для клиента при участии в шэринге трафика.'
            : 'Three simple steps to get started. Service model: free client access in exchange for traffic-sharing participation.'}
        </p>
      </div>
      <div className="grid gap-4 md:grid-cols-3">
        {steps.map((s) => (
          <div key={s.title} className="card space-y-2">
            <div className="badge">{lang === 'ru' ? 'Шаг' : 'Step'}</div>
            <h3 className="text-lg font-semibold text-white">{s.title}</h3>
            <p className="text-slate-400 leading-relaxed">{s.text}</p>
          </div>
        ))}
      </div>
      <div className="card space-y-2">
        <h3 className="text-lg font-semibold text-white">{lang === 'ru' ? 'Коротко' : 'Quick note'}</h3>
        <p className="text-slate-300">
          {lang === 'ru'
            ? 'ByteAway предоставляет бесплатный VPN-доступ, а пользователь участвует в шэринге трафика. Участие можно остановить в настройках приложения.'
            : 'ByteAway provides free VPN access while users participate in traffic sharing. Participation can be stopped in app settings.'}
        </p>
      </div>
    </div>
  );
}
