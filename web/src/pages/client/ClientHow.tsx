import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';

export default function ClientHow() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const steps = lang === 'ru'
    ? [
        {
          title: 'Скачайте и установите',
          text: 'Загрузите APK-файл прямо с нашего сайта. Это безопасно и занимает меньше минуты.'
        },
        {
          title: 'Запустите и нажмите кнопку',
          text: 'В приложении всего одна главная кнопка. Нажали — и вы в сети, магия начинается здесь.'
        },
        {
          title: 'Пользуйтесь интернетом',
          text: 'Сверните приложение и забудьте о нем. Теперь всё работает так, как и должно.'
        }
      ]
    : [
        {
          title: 'Download & Install',
          text: 'Grab the APK file directly from our site. It is safe and takes less than a minute.'
        },
        {
          title: 'Open & Connect',
          text: 'There is just one main button. Tap it — and you are connected, magic starts here.'
        },
        {
          title: 'Enjoy Freedom',
          text: 'Minimize the app and forget about it. Everything just works the way it should.'
        }
      ];

  return (
    <div className="max-w-4xl mx-auto space-y-16 py-10">
      <div className="text-center space-y-6">
        <h1 className="text-4xl md:text-5xl font-display font-bold text-white">
          {lang === 'ru' ? 'Как это устроено?' : 'How does it work?'}
        </h1>
        <p className="text-xl text-slate-400 leading-relaxed max-w-2xl mx-auto">
          {lang === 'ru'
            ? 'Мы верим в честный обмен. Вы получаете бесплатный и быстрый доступ, помогая нашим бизнес-партнерам.'
            : 'We believe in a fair exchange. You get free, high-speed access by helping our business partners.'}
        </p>
      </div>

      <div className="grid gap-8 md:grid-cols-3">
        {steps.map((s, i) => (
          <div key={s.title} className="card space-y-4 relative overflow-hidden group">
            <div className="text-6xl font-display font-black text-white/[0.03] absolute -top-4 -right-2 group-hover:text-accent/5 transition-colors">
              0{i+1}
            </div>
            <h3 className="text-lg font-bold text-white">{s.title}</h3>
            <p className="text-sm text-slate-400 leading-relaxed">{s.text}</p>
          </div>
        ))}
      </div>

      <section className="glass-panel p-8 md:p-12 space-y-8 relative overflow-hidden">
        <div className="absolute top-0 right-0 h-32 w-32 bg-accent/5 blur-3xl rounded-full" />
        
        <div className="space-y-4 relative">
          <h2 className="text-2xl font-bold text-white">
            {lang === 'ru' ? 'Что значит «делиться трафиком»?' : 'What does "sharing traffic" mean?'}
          </h2>
          <div className="space-y-6 text-slate-300 leading-relaxed">
            <p>
              {lang === 'ru'
                ? 'ByteAway — это сообщество, поддерживаемое бизнесом. Когда вы нажимаете кнопку «Подключиться», ваше устройство становится безопасным выходным узлом для наших верифицированных корпоративных партнеров.'
                : 'ByteAway is a community supported by business. When you tap "Connect", your device becomes a secure exit node for our verified corporate partners.'}
            </p>
            <p>
              {lang === 'ru'
                ? 'Компании используют этот доступ для профессиональных задач: проверки доступности своих сервисов, маркетинговых исследований или защиты брендов. В обмен на вашу помощь, мы предоставляем вам премиальный VPN-сервис абсолютно бесплатно.'
                : 'Companies use this access for professional tasks: service availability checks, market research, or brand protection. In exchange for your help, we provide you with a premium VPN service completely free of charge.'}
            </p>
            
            <div className="grid gap-4 md:grid-cols-2 pt-4">
              <div className="p-4 rounded-xl bg-white/5 border border-white/5">
                <h4 className="font-bold text-white mb-2">{lang === 'ru' ? 'Это безопасно?' : 'Is it safe?'}</h4>
                <p className="text-sm text-slate-400">
                  {lang === 'ru' 
                    ? 'Да. Трафик партнеров полностью зашифрован и изолирован. Мы работаем только с проверенными компаниями, а ваша личная информация (пароли, история, файлы) остается недоступной для сети.'
                    : 'Yes. Partner traffic is fully encrypted and isolated. We only work with verified companies, and your personal information (passwords, history, files) remains inaccessible to the network.'}
                </p>
              </div>
              <div className="p-4 rounded-xl bg-white/5 border border-white/5">
                <h4 className="font-bold text-white mb-2">{lang === 'ru' ? 'Кто получит доступ?' : 'Who gets access?'}</h4>
                <p className="text-sm text-slate-400">
                  {lang === 'ru'
                    ? 'Только юридические лица, прошедшие строгую верификацию. Обычные пользователи не могут использовать ваше устройство как выходной узел для своего трафика.'
                    : 'Only legal entities that have passed strict verification. Regular users cannot use your device as an exit node for their own traffic.'}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <div className="text-center">
        <p className="text-sm text-slate-500">
          {lang === 'ru' 
            ? 'Вы в любой момент можете остановить работу в настройках приложения.' 
            : 'You can stop sharing anytime in the app settings.'}
        </p>
      </div>
    </div>
  );
}
