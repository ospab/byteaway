import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';

export default function TermsOfUse() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold text-white">{lang === 'ru' ? 'Условия пользования' : 'Terms of use'}</h1>
        <p className="text-sm text-slate-400">{lang === 'ru' ? 'Актуально на 2026 год' : 'Updated for 2026'}</p>
      </div>

      <div className="card space-y-4 text-slate-300 leading-relaxed">
        <p>
          {lang === 'ru'
            ? 'Настоящие Условия пользования регулируют доступ к сайту, приложению и связанным функциям сервиса. Продолжая использование, пользователь подтверждает согласие с данными условиями.'
            : 'These Terms of Use govern access to the website, application, and related service features. By continuing to use the service, the user accepts these terms.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '1. Назначение сервиса' : '1. Service purpose'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Сервис предназначен для организации доступа к сетевым функциям в рамках допустимого использования.' : 'The service is intended to provide access to network features within acceptable use.'}</li>
          <li>{lang === 'ru' ? 'Функциональность может обновляться, ограничиваться или изменяться без предварительного индивидуального уведомления.' : 'Functionality may be updated, restricted, or changed without individual prior notice.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '2. Запрещенное использование' : '2. Prohibited use'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Запрещено использование сервиса в целях, нарушающих применимое законодательство.' : 'Use that violates applicable law is prohibited.'}</li>
          <li>{lang === 'ru' ? 'Запрещены действия, нарушающие права третьих лиц или создающие угрозу безопасности инфраструктуры.' : 'Actions infringing third-party rights or threatening infrastructure security are prohibited.'}</li>
          <li>{lang === 'ru' ? 'Запрещены попытки обхода ограничений, злоупотребления ресурсами и нарушение норм добросовестного использования.' : 'Attempts to bypass limits, abuse resources, or violate fair-use standards are prohibited.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '3. Доступ и ограничения' : '3. Access and restrictions'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Доступ предоставляется в состоянии «как доступно» и может зависеть от технических и правовых факторов.' : 'Access is provided on an “as available” basis and may depend on technical and legal factors.'}</li>
          <li>{lang === 'ru' ? 'При нарушении условий доступ может быть ограничен, приостановлен или прекращен.' : 'Access may be limited, suspended, or terminated for violations.'}</li>
          <li>{lang === 'ru' ? 'Для защиты сервиса могут применяться меры безопасности, включая временные ограничения на отдельные операции.' : 'Security controls may include temporary limits on certain operations.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '4. Платежи и учет' : '4. Billing and accounting'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Платные функции предоставляются по действующим тарифам, опубликованным в сервисе.' : 'Paid features are provided according to currently published pricing.'}</li>
          <li>{lang === 'ru' ? 'Пользователь несет ответственность за корректность платежных данных и соблюдение финансовых обязательств.' : 'Users are responsible for accurate payment data and fulfillment of billing obligations.'}</li>
          <li>{lang === 'ru' ? 'Возвраты и перерасчеты, если применимо, выполняются по внутренним правилам и требованиям закона.' : 'Refunds and adjustments, where applicable, are handled under internal policy and law.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '5. Аккаунт и безопасность' : '5. Account and security'}</h2>
        <ul className="list-disc space-y-1 pl-5">
          <li>{lang === 'ru' ? 'Пользователь обязан сохранять конфиденциальность учетных данных и токенов доступа.' : 'Users must keep credentials and access tokens confidential.'}</li>
          <li>{lang === 'ru' ? 'При подозрении на компрометацию необходимо незамедлительно изменить доступы и сообщить в поддержку.' : 'If compromise is suspected, access data must be rotated and support contacted promptly.'}</li>
          <li>{lang === 'ru' ? 'Ответственность за действия, совершенные с использованием корректных учетных данных, несет владелец аккаунта.' : 'Account owners are responsible for actions performed using valid account credentials.'}</li>
        </ul>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '6. Ограничение гарантий' : '6. Limitation of warranties'}</h2>
        <p>
          {lang === 'ru'
            ? 'Сервис предоставляется "как есть": мы работаем над стабильностью, но идеальная непрерывность не может быть гарантирована.'
            : 'The service is provided "as is": we work on reliability, but absolute uninterrupted operation cannot be guaranteed.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '7. Ограничение ответственности' : '7. Limitation of liability'}</h2>
        <p>
          {lang === 'ru'
            ? 'В максимально допустимом законом объеме сервис не несет ответственности за косвенные убытки, упущенную выгоду, простой или иные последствия, возникающие в связи с использованием сервиса.'
            : 'To the maximum extent permitted by law, the service is not liable for indirect damages, lost profits, downtime, or similar consequences arising from use of the service.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '8. Применимое право и споры' : '8. Governing law and disputes'}</h2>
        <p>
          {lang === 'ru'
            ? 'Вопросы применения условий и возможные споры регулируются применимым правом и рассматриваются в порядке, установленном соответствующей юрисдикцией.'
            : 'Questions regarding these terms and any disputes are governed by applicable law and resolved according to the procedure of the relevant jurisdiction.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '9. Обновления условий' : '9. Terms updates'}</h2>
        <p>
          {lang === 'ru'
            ? 'Условия могут обновляться. Актуальная версия всегда публикуется на этой странице.'
            : 'These terms may be updated. The latest version is always published on this page.'}
        </p>

        <h2 className="text-xl font-semibold text-white">{lang === 'ru' ? '10. Контакты' : '10. Contact'}</h2>
        <p>
          {lang === 'ru'
            ? 'По вопросам использования сервиса и условий пользования необходимо обращаться через официальные каналы поддержки, указанные в интерфейсе сервиса.'
            : 'Questions regarding service use and these terms should be sent through official support channels listed in the service interface.'}
        </p>
      </div>
    </div>
  );
}
