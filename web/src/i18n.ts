export type Locale = 'ru' | 'en';

export function normalizeLocale(value?: string): Locale {
  return value === 'en' ? 'en' : 'ru';
}

export function withLocale(locale: Locale, path: string): string {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `/${locale}${normalizedPath}`;
}

export function switchLocalePath(pathname: string, target: Locale): string {
  if (/^\/(ru|en)(\/|$)/.test(pathname)) {
    return pathname.replace(/^\/(ru|en)/, `/${target}`);
  }

  return withLocale(target, '/client');
}
