import { FormEvent, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { normalizeLocale, withLocale } from '../../i18n';
import { extractApiErrorMessage, registerBusiness } from '../../api/client';
import TurnstileWidget from '../../components/TurnstileWidget';

const BUSINESS_SESSION_KEY = 'byteaway_business_session';
const BUSINESS_SESSION_TOKEN_KEY = 'byteaway_business_session_token';
const BUSINESS_EMAIL_KEY = 'byteaway_business_email';
const BUSINESS_COMPANY_KEY = 'byteaway_business_company';
const TOKEN_KEY = 'byteaway_bearer_token';

export default function BusinessRegister() {
  const { locale } = useParams();
  const lang = normalizeLocale(locale);
  const navigate = useNavigate();
  const [company, setCompany] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [captchaToken, setCaptchaToken] = useState('');
  const [error, setError] = useState('');

  const [isSubmitting, setIsSubmitting] = useState(false);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');

    if (!company.trim() || !email.trim() || !password.trim()) {
      setError(lang === 'ru' ? 'Заполните все обязательные поля.' : 'Fill in all required fields.');
      return;
    }

    if (password !== confirmPassword) {
      setError(lang === 'ru' ? 'Пароли не совпадают.' : 'Passwords do not match.');
      return;
    }

    if (!captchaToken) {
      setError(lang === 'ru' ? 'Подтвердите капчу.' : 'Complete captcha verification.');
      return;
    }

    try {
      setIsSubmitting(true);
      const auth = await registerBusiness({
        company_name: company.trim(),
        email: email.trim(),
        password,
        captcha_token: captchaToken,
      });

      localStorage.setItem(BUSINESS_SESSION_KEY, '1');
      localStorage.setItem(BUSINESS_SESSION_TOKEN_KEY, auth.session_token);
      localStorage.setItem(BUSINESS_EMAIL_KEY, auth.email);
      localStorage.setItem(BUSINESS_COMPANY_KEY, auth.company_name);
      localStorage.removeItem(TOKEN_KEY);

      navigate(withLocale(lang, '/business/console'));
    } catch (err) {
      const message = extractApiErrorMessage(err, 'Registration failed');
      setError(lang === 'ru' ? `Ошибка регистрации: ${message}` : `Registration error: ${message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="mx-auto w-full max-w-xl">
      <div className="card space-y-6">
        <div className="space-y-2">
          <p className="badge">Business Onboarding</p>
          <h1 className="text-3xl font-bold text-white">
            {lang === 'ru' ? 'Регистрация компании' : 'Company registration'}
          </h1>
          <p className="text-slate-300">
            {lang === 'ru'
              ? 'Создайте рабочий кабинет и настройте доступ для вашей команды.'
              : 'Create your workspace and configure access for your team.'}
          </p>
        </div>

        <form className="space-y-4" onSubmit={onSubmit}>
          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Название компании' : 'Company name'}</label>
            <input
              className="input"
              value={company}
              onChange={(e) => setCompany(e.target.value)}
              placeholder={lang === 'ru' ? 'ООО Пример' : 'Example Ltd'}
            />
          </div>

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Корпоративный email' : 'Business email'}</label>
            <input
              className="input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              type="email"
              placeholder={lang === 'ru' ? 'team@company.com' : 'team@company.com'}
            />
          </div>

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Пароль' : 'Password'}</label>
            <input
              className="input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              placeholder={lang === 'ru' ? 'Создайте пароль' : 'Create password'}
            />
          </div>

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Подтверждение пароля' : 'Confirm password'}</label>
            <input
              className="input"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              type="password"
              placeholder={lang === 'ru' ? 'Повторите пароль' : 'Repeat password'}
            />
          </div>

          {error && <p className="text-sm text-red-400">{error}</p>}

          <div className="space-y-1">
            <label className="text-sm text-slate-300">{lang === 'ru' ? 'Проверка безопасности' : 'Security verification'}</label>
            <TurnstileWidget onTokenChange={setCaptchaToken} />
          </div>

          <div className="flex flex-wrap items-center gap-3 pt-1">
            <button className="btn-primary" type="submit" disabled={isSubmitting}>
              {isSubmitting
                ? (lang === 'ru' ? 'Регистрация...' : 'Creating account...')
                : (lang === 'ru' ? 'Зарегистрироваться' : 'Create account')}
            </button>
            <Link className="btn-ghost" to={withLocale(lang, '/business/login')}>
              {lang === 'ru' ? 'Уже есть аккаунт' : 'Already have an account'}
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
