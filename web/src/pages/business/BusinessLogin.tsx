import { FormEvent, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';
import { extractApiErrorMessage, loginBusiness } from '../../api/client';
import TurnstileWidget from '../../components/TurnstileWidget';

const BUSINESS_SESSION_KEY = 'byteaway_business_session';
const BUSINESS_SESSION_TOKEN_KEY = 'byteaway_business_session_token';
const TOKEN_KEY = 'byteaway_bearer_token';
const BUSINESS_EMAIL_KEY = 'byteaway_business_email';

export default function BusinessLogin() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const navigate = useNavigate();
  const [email, setEmail] = useState(localStorage.getItem(BUSINESS_EMAIL_KEY) || '');
  const [password, setPassword] = useState('');
  const [captchaToken, setCaptchaToken] = useState('');
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');

    if (!email.trim() || !password.trim()) {
      setError(lang === 'ru' ? 'Укажите email и пароль.' : 'Provide email and password.');
      return;
    }

    if (!captchaToken) {
      setError(lang === 'ru' ? 'Подтвердите капчу.' : 'Complete captcha verification.');
      return;
    }

    try {
      setIsSubmitting(true);
      const auth = await loginBusiness({
        email: email.trim(),
        password,
        captcha_token: captchaToken,
      });

      localStorage.setItem(BUSINESS_SESSION_KEY, '1');
      localStorage.setItem(BUSINESS_SESSION_TOKEN_KEY, auth.session_token);
      localStorage.setItem(BUSINESS_EMAIL_KEY, auth.email);
      localStorage.removeItem(TOKEN_KEY);

      navigate(withLocale(lang, '/business/console'));
    } catch (err) {
      const message = extractApiErrorMessage(err, 'Login failed');
      setError(lang === 'ru' ? `Ошибка входа: ${message}` : `Login error: ${message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="mx-auto w-full max-w-xl">
      <div className="card space-y-6">
        <div className="space-y-2">
          <p className="badge">Business Access</p>
          <h1 className="text-3xl font-bold text-white">
            {lang === 'ru' ? 'Вход в корпоративный кабинет' : 'Business account login'}
          </h1>
          <p className="text-slate-300">
            {lang === 'ru'
              ? 'Авторизуйтесь для доступа к панели управления и рабочим инструментам.'
              : 'Sign in to access your operations console and business tools.'}
          </p>
        </div>

        <form className="space-y-4" onSubmit={onSubmit}>
          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Email' : 'Email'}</label>
            <input
              className="input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={lang === 'ru' ? 'ops@company.com' : 'ops@company.com'}
              type="email"
            />
          </div>

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Пароль' : 'Password'}</label>
            <input
              className="input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder={lang === 'ru' ? 'Введите пароль' : 'Enter password'}
              type="password"
            />
          </div>

          {error && <p className="text-sm text-red-400">{error}</p>}

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Проверка безопасности' : 'Security verification'}</label>
            <TurnstileWidget onTokenChange={setCaptchaToken} />
          </div>

          <div className="flex flex-wrap items-center gap-3 pt-1">
            <button className="btn-primary" type="submit" disabled={isSubmitting}>
              {isSubmitting ? (lang === 'ru' ? 'Вход...' : 'Signing in...') : (lang === 'ru' ? 'Войти' : 'Sign in')}
            </button>
            <Link className="btn-ghost" to={withLocale(lang, '/business/register')}>
              {lang === 'ru' ? 'Регистрация' : 'Create account'}
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
