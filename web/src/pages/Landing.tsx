import { Link } from 'react-router-dom';

export default function Landing() {
  return (
    <div className="container">
      <section className="hero">
        <div className="badge">VPN + резидентные прокси</div>
        <h1 style={{ fontSize: 42, margin: 0 }}>Быстрый доступ к интернету без ограничений</h1>
        <p style={{ color: 'var(--muted)', maxWidth: 620 }}>
          Бесплатный VPN для пользователей. Резидентные прокси для бизнеса. Одна сеть на базе Android
          устройств с честным биллингом по трафику.
        </p>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <Link to="/download"><button>Скачать приложение</button></Link>
          <Link to="/business"><button className="ghost">ЛК для B2B</button></Link>
        </div>
      </section>

      <section className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', marginTop: 32 }}>
        {[{ title: 'Reality + VLESS', text: 'Маскировка под TLS, обходит DPI и блокировки.' },
          { title: 'Резидентные IP', text: 'Трафик идет через реальные домашние устройства.' },
          { title: 'Честный биллинг', text: 'Оплата только за фактически переданные байты.' },
          { title: 'API ключи', text: 'Выдайте SOCKS5 креды за 10 секунд через ЛК.' }].map((item) => (
          <div key={item.title} className="card">
            <h3>{item.title}</h3>
            <p style={{ color: 'var(--muted)' }}>{item.text}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
