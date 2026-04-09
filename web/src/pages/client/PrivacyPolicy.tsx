import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';

export default function PrivacyPolicy() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold text-white">
          {lang === 'ru' ? 'Политика конфиденциальности' : 'Privacy policy'}
        </h1>
        <p className="text-sm text-slate-400">{lang === 'ru' ? 'Актуально на 2026 год' : 'Updated for 2026'}</p>
      </div>

      <div className="card space-y-4 text-slate-300 leading-relaxed">
        <p>
          {lang === 'ru'
            ? 'Настоящая Политика конфиденциальности описывает, какие данные могут обрабатываться при использовании сайта и приложения, в каких целях это делается и какие права есть у пользователя.'
            : 'This Privacy Policy explains what data may be processed when using the website and application, why such processing is needed, and what rights users have.'}
        </p>
        <p>
          {lang === 'ru'
            ? 'Документ сформулирован в обезличенном виде и применяется ко всем пользователям сервиса на равных условиях, если иное не предусмотрено применимым законодательством.'
            : 'This document is intentionally anonymized and applies to all users under equal conditions unless otherwise required by applicable law.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '1. Какие данные обрабатываются' : '1. Data we process'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>
            {lang === 'ru'
              ? 'Идентификационные и учетные данные, необходимые для авторизации, управления доступом и сопровождения аккаунта.'
              : 'Identification and account data required for sign-in, access control, and account support.'}
          </li>
          <li>
            {lang === 'ru'
              ? 'Технические данные работы сервиса: временные метки запросов, события доступа, служебные журналы и диагностические записи.'
              : 'Technical service-operation data: request timestamps, access events, service logs, and diagnostic records.'}
          </li>
          <li>
            {lang === 'ru'
              ? 'Данные об использовании в агрегированном или операционном виде, необходимые для учета, поддержки и предотвращения злоупотреблений.'
              : 'Usage data in aggregated or operational form required for accounting, support, and abuse prevention.'}
          </li>
          <li>
            {lang === 'ru'
              ? 'Платежные и расчетные сведения в пределах, необходимых для биллинга, отчетности и выполнения финансовых обязательств.'
              : 'Billing and payment-related information to the extent required for billing, reporting, and financial compliance.'}
          </li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '2. Цели обработки' : '2. Processing purposes'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Предоставление доступа к функциям сервиса.' : 'Providing access to service features.'}</li>
          <li>{lang === 'ru' ? 'Поддержание стабильности и безопасности работы.' : 'Maintaining operational stability and security.'}</li>
          <li>{lang === 'ru' ? 'Обработка пользовательских обращений и технических инцидентов.' : 'Handling support requests and technical incidents.'}</li>
          <li>{lang === 'ru' ? 'Выполнение обязательств по учету, оплатам и правовому соответствию.' : 'Meeting accounting, billing, and legal compliance obligations.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '3. Что не выполняется' : '3. What we do not do'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Персональные данные не продаются третьим лицам.' : 'Personal data is not sold to third parties.'}</li>
          <li>{lang === 'ru' ? 'Данные не используются для рекламного таргетинга.' : 'Data is not used for ad-targeting purposes.'}</li>
          <li>{lang === 'ru' ? 'Не публикуются сведения, позволяющие идентифицировать конкретного пользователя без законного основания.' : 'No user-identifying information is disclosed without a legal basis.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '4. Хранение и защита' : '4. Storage and protection'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Срок хранения данных ограничивается целями обработки и требованиями законодательства.' : 'Retention periods are limited by processing purposes and legal requirements.'}</li>
          <li>{lang === 'ru' ? 'Применяются организационные и технические меры защиты доступа.' : 'Organizational and technical access-protection measures are applied.'}</li>
          <li>{lang === 'ru' ? 'Доступ к данным предоставляется только уполномоченным процессам и лицам в рамках их задач.' : 'Data access is restricted to authorized processes and personnel on a need-to-know basis.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '5. Права пользователя' : '5. User rights'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Запросить сведения об обработке данных в пределах, предусмотренных законодательством.' : 'Request information about personal data processing as permitted by law.'}</li>
          <li>{lang === 'ru' ? 'Запросить исправление неточных данных.' : 'Request correction of inaccurate data.'}</li>
          <li>{lang === 'ru' ? 'Запросить удаление данных, если это не противоречит обязательным требованиям хранения.' : 'Request deletion where retention is not required by mandatory obligations.'}</li>
          <li>{lang === 'ru' ? 'Отозвать согласие на отдельные виды обработки, если такое согласие являлось основанием.' : 'Withdraw consent for specific processing where consent was the legal basis.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '6. Передача данных третьим сторонам' : '6. Sharing with third parties'}</h2>
        <p>
          {lang === 'ru'
            ? 'Передача данных возможна только в случаях, необходимых для работы сервиса, выполнения договора, соблюдения закона или защиты прав и безопасности. В таких случаях передаются только минимально необходимые данные.'
            : 'Data may be shared only when required to operate the service, perform contractual obligations, comply with law, or protect rights and security. In such cases, only the minimum necessary data is shared.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '7. Международная обработка' : '7. Cross-border processing'}</h2>
        <p>
          {lang === 'ru'
            ? 'Если обработка данных выполняется в другой юрисдикции, применяются разумные меры защиты и правовые механизмы, предусмотренные применимым правом.'
            : 'If data processing occurs in another jurisdiction, reasonable safeguards and legal mechanisms are applied as required by applicable law.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '8. Изменения политики' : '8. Policy updates'}</h2>
        <p>
          {lang === 'ru'
            ? 'Политика может обновляться. Новая редакция публикуется на этой странице с актуальной датой.'
            : 'This policy may be updated. The latest revision is published on this page with the current date.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '9. Обратная связь' : '9. Contact and requests'}</h2>
        <p>
          {lang === 'ru'
            ? 'Запросы по вопросам конфиденциальности принимаются через официальные каналы поддержки, указанные в интерфейсе сервиса.'
            : 'Privacy-related requests can be submitted via official support channels listed in the service interface.'}
        </p>
      </div>
    </div>
  );
}
