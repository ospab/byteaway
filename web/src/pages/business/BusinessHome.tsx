import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';

const pillars = [
  {
    title: 'Корпоративная безопасность',
    text: 'Единые правила доступа, журналирование действий и контролируемая работа с учетными данными для команд и подрядчиков.'
  },
  {
    title: 'Управление доступом',
    text: 'Выдача и отзыв рабочих доступов по ролям, прозрачная атрибуция использования и понятный жизненный цикл ключей.'
  },
  {
    title: 'Надежная эксплуатация',
    text: 'Стабильная инфраструктура, мониторинг и предсказуемые процессы для ежедневных бизнес-задач.'
  }
];

const useCases = [
  'Корпоративные интеграции и тестовые среды',
  'Проверка доступности сервисов в разных регионах',
  'Поддержка внутренних команд разработки и QA',
  'Контролируемая работа с внешними подрядчиками'
];

export default function BusinessHome() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  const t = {
    badge: lang === 'ru' ? 'ByteAway для бизнеса' : 'ByteAway for Business',
    title: lang === 'ru'
      ? 'Безопасная B2B-платформа для управляемого сетевого доступа и рабочих интеграций'
      : 'A secure B2B platform for controlled network access and enterprise operations',
    lead: lang === 'ru'
      ? 'Решение ориентировано на корпоративные политики: авторизация, разграничение прав, централизованный контроль и прозрачная операционная отчетность.'
      : 'Built around corporate controls: authentication, role-based access, centralized governance, and transparent operational reporting.',
    login: lang === 'ru' ? 'Вход в кабинет' : 'Business login',
    register: lang === 'ru' ? 'Регистрация компании' : 'Company registration',
    operationsTitle: lang === 'ru' ? 'Для реальных бизнес-процессов' : 'Designed for real business operations',
    securityTitle: lang === 'ru' ? 'Контроль и соответствие' : 'Security and compliance',
    startTitle: lang === 'ru' ? 'Подключение в три шага' : 'Get started in three steps',
    step1Title: lang === 'ru' ? 'Регистрация' : 'Register company',
    step1Text: lang === 'ru'
      ? 'Создайте корпоративный аккаунт и укажите рабочие контактные данные.'
      : 'Create your corporate account and provide your business contact details.',
    step2Title: lang === 'ru' ? 'Вход и настройка' : 'Sign in and configure',
    step2Text: lang === 'ru'
      ? 'Авторизуйтесь в кабинете и настройте доступы для ваших команд.'
      : 'Sign in to the console and configure access for your teams.',
    step3Title: lang === 'ru' ? 'Работа в консоли' : 'Operate in console',
    step3Text: lang === 'ru'
      ? 'Используйте инструменты кабинета для повседневных операций и контроля.'
      : 'Use the console for day-to-day operations, control, and reporting.'
  };

  const localizedPillars = lang === 'ru'
    ? [
        {
          title: 'Корпоративная безопасность',
          text: 'Единые правила доступа, журналирование действий и контролируемая работа с учетными данными для команд и подрядчиков.'
        },
        {
          title: 'Управление доступом',
          text: 'Выдача и отзыв рабочих доступов по ролям, прозрачная атрибуция использования и понятный жизненный цикл ключей.'
        },
        {
          title: 'Надежная эксплуатация',
          text: 'Стабильная инфраструктура, мониторинг и предсказуемые процессы для ежедневных бизнес-задач.'
        }
      ]
    : [
        {
          title: 'Enterprise security',
          text: 'Unified access rules, action logging, and controlled credential handling for teams and contractors.'
        },
        {
          title: 'Access governance',
          text: 'Issue and revoke operational access by role with clear attribution and auditable lifecycle controls.'
        },
        {
          title: 'Operational reliability',
          text: 'Stable infrastructure, observability, and predictable workflows for day-to-day business usage.'
        }
      ];

  const localizedUseCases = lang === 'ru'
    ? [
        'Корпоративные интеграции и тестовые среды',
        'Проверка доступности сервисов в разных регионах',
        'Поддержка внутренних команд разработки и QA',
        'Контролируемая работа с внешними подрядчиками'
      ]
    : [
        'Enterprise integrations and staging workflows',
        'Service availability checks across regions',
        'Support for internal engineering and QA teams',
        'Controlled collaboration with external vendors'
      ];

  return (
    <div className="space-y-10">
      <section className="relative overflow-hidden rounded-3xl border border-slate-800/70 bg-panel/70 p-8 md:p-12">
        <div className="absolute -right-12 -top-12 h-44 w-44 rounded-full bg-cyan-400/15 blur-3xl" />
        <div className="absolute -bottom-16 left-10 h-44 w-44 rounded-full bg-emerald-300/10 blur-3xl" />

        <div className="relative space-y-6">
          <p className="badge">{t.badge}</p>
          <h1 className="max-w-4xl text-4xl font-bold leading-tight text-white md:text-5xl">
            {t.title}
          </h1>
          <p className="max-w-3xl text-lg text-slate-300">
            {t.lead}
          </p>
          <div className="flex flex-wrap gap-3">
            <Link to={withLocale(lang, '/business/login')} className="btn-primary">{t.login}</Link>
            <Link to={withLocale(lang, '/business/register')} className="btn-ghost">{t.register}</Link>
          </div>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        {localizedPillars.map((item) => (
          <article key={item.title} className="card space-y-3">
            <h2 className="text-xl font-semibold text-white">{item.title}</h2>
            <p className="text-slate-300 leading-relaxed">{item.text}</p>
          </article>
        ))}
      </section>

      <section className="grid gap-4 md:grid-cols-2">
        <article className="card space-y-4">
          <h2 className="text-2xl font-semibold text-white">{t.operationsTitle}</h2>
          <ul className="space-y-2 text-slate-300">
            {localizedUseCases.map((uc) => (
              <li key={uc}>• {uc}</li>
            ))}
          </ul>
        </article>

        <article id="security" className="card space-y-4">
          <h2 className="text-2xl font-semibold text-white">{t.securityTitle}</h2>
          <div className="space-y-2 text-slate-300">
            <p>{lang === 'ru' ? 'Шифрование трафика и безопасные каналы доступа для API-операций.' : 'Encrypted transport and secure access channels for operational APIs.'}</p>
            <p>{lang === 'ru' ? 'Авторизация и аудит действий в административном контуре.' : 'Authentication and auditable administration actions.'}</p>
            <p>{lang === 'ru' ? 'Изолированные сервисные роли для эксплуатационных задач.' : 'Isolated service roles for operational workloads.'}</p>
            <p>{lang === 'ru' ? 'Наблюдаемость и диагностика для контроля SLA и инцидентов.' : 'Observability and diagnostics for SLA control and incident response.'}</p>
          </div>
        </article>
      </section>

      <section className="card space-y-5">
        <h2 className="text-2xl font-semibold text-white">{t.startTitle}</h2>
        <div className="grid gap-4 md:grid-cols-3">
          <div className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5">
            <p className="text-sm text-cyan-300">Step 1</p>
            <h3 className="mt-2 text-lg font-semibold text-white">{t.step1Title}</h3>
            <p className="mt-2 text-slate-300">{t.step1Text}</p>
          </div>
          <div className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5">
            <p className="text-sm text-cyan-300">Step 2</p>
            <h3 className="mt-2 text-lg font-semibold text-white">{t.step2Title}</h3>
            <p className="mt-2 text-slate-300">{t.step2Text}</p>
          </div>
          <div className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5">
            <p className="text-sm text-cyan-300">Step 3</p>
            <h3 className="mt-2 text-lg font-semibold text-white">{t.step3Title}</h3>
            <p className="mt-2 text-slate-300">{t.step3Text}</p>
          </div>
        </div>
      </section>
    </div>
  );
}
