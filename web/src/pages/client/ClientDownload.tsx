import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { normalizeLocale } from '../../i18n';
import { createDownloadTicket } from '../../api/client';
import TurnstileWidget from '../../components/TurnstileWidget';

export default function ClientDownload() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const [captchaToken, setCaptchaToken] = useState('');
  const [downloadError, setDownloadError] = useState('');
  const [isLoadingTicket, setIsLoadingTicket] = useState(false);

  const requestDownload = async () => {
    setDownloadError('');
    if (!captchaToken) {
      setDownloadError(lang === 'ru' ? 'Подтвердите капчу перед скачиванием.' : 'Complete captcha verification before downloading.');
      return;
    }

    try {
      setIsLoadingTicket(true);
      const response = await createDownloadTicket(captchaToken);
      window.location.assign(response.download_url);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Download request failed';
      setDownloadError(lang === 'ru' ? `Ошибка скачивания: ${message}` : `Download error: ${message}`);
    } finally {
      setIsLoadingTicket(false);
    }
  };

  return (
    <div className="space-y-8">
      <div className="space-y-3">
        <p className="badge">ByteAway Android</p>
        <h1 className="text-3xl font-bold text-white md:text-4xl">
          {lang === 'ru' ? 'Скачивание Android клиента' : 'Android app download'}
        </h1>
        <p className="max-w-3xl text-slate-300">
          {lang === 'ru'
            ? 'Здесь всегда доступна актуальная версия приложения для Android.'
            : 'The latest Android version is always available on this page.'}
        </p>
      </div>

      <section className="card space-y-5">
        <div className="space-y-3">
          <h2 className="text-2xl font-semibold text-white">Android APK</h2>
          <p className="text-slate-300">
            {lang === 'ru'
              ? 'Скачайте приложение по кнопке ниже и установите его на устройство.'
              : 'Download the app with the button below and install it on your device.'}
          </p>
          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Проверка безопасности' : 'Security verification'}</label>
            <TurnstileWidget onTokenChange={setCaptchaToken} />
          </div>
          <div className="flex flex-wrap gap-3 pt-1">
            <button className="btn-primary" onClick={requestDownload} disabled={isLoadingTicket}>
              {isLoadingTicket
                ? (lang === 'ru' ? 'Подготовка...' : 'Preparing...')
                : (lang === 'ru' ? 'Скачать APK' : 'Download APK')}
            </button>
          </div>
          {downloadError && <p className="text-sm text-red-400">{downloadError}</p>}
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5 text-slate-300">
          <p className="text-sm text-cyan-300">Step 1</p>
          <p className="mt-2">{lang === 'ru' ? 'Скачайте APK по кнопке выше.' : 'Download the APK using the button above.'}</p>
        </article>
        <article className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5 text-slate-300">
          <p className="text-sm text-cyan-300">Step 2</p>
          <p className="mt-2">{lang === 'ru' ? 'Разрешите установку из этого источника в настройках Android.' : 'Allow installation from this source in Android settings.'}</p>
        </article>
        <article className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5 text-slate-300">
          <p className="text-sm text-cyan-300">Step 3</p>
          <p className="mt-2">{lang === 'ru' ? 'При первом запуске подтвердите VPN-разрешение.' : 'Confirm VPN permission on first launch.'}</p>
        </article>
      </section>

      <p className="text-sm text-slate-400">
        {lang === 'ru' ? 'iOS-версия пока недоступна.' : 'iOS version is not available yet.'}
      </p>
    </div>
  );
}
