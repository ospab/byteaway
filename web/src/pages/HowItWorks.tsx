export default function HowItWorks() {
  const steps = [
    { title: 'Пользователь', text: 'Ставит приложение, включает VPN и шаринг по Wi‑Fi.' },
    { title: 'Мастер-нода', text: 'Rust-сервис раздает конфиги, биллингует трафик, управляет WebSocket туннелями.' },
    { title: 'B2B клиент', text: 'Получает SOCKS5 доступ c фильтрацией по стране и типу соединения.' }
  ];
  return (
    <div className="container" style={{ paddingBottom: 40 }}>
      <h1>Как это работает</h1>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))' }}>
        {steps.map((s) => (
          <div key={s.title} className="card">
            <h3>{s.title}</h3>
            <p style={{ color: 'var(--muted)' }}>{s.text}</p>
          </div>
        ))}
      </div>
      <div className="card" style={{ marginTop: 24 }}>
        <h3>Поток трафика</h3>
        <p style={{ color: 'var(--muted)' }}>
          SOCKS5 → мастер-нода → WebSocket reverse туннель → устройство пользователя → интернет. Каждый мегабайт
          учитывается в Redis и списывается в PostgreSQL воркером.
        </p>
      </div>
    </div>
  );
}
