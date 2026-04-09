import { useEffect, useRef, useState } from 'react';

type TurnstileWidgetProps = {
  onTokenChange: (token: string) => void;
};

function ensureTurnstileScript(): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>('script[data-turnstile="true"]');
    if (existing) {
      if ((window as Window & { turnstile?: unknown }).turnstile) {
        resolve();
      } else {
        existing.addEventListener('load', () => resolve(), { once: true });
        existing.addEventListener('error', () => reject(new Error('Failed to load Turnstile')), { once: true });
      }
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async = true;
    script.defer = true;
    script.setAttribute('data-turnstile', 'true');
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load Turnstile'));
    document.head.appendChild(script);
  });
}

export default function TurnstileWidget({ onTokenChange }: TurnstileWidgetProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const widgetIdRef = useRef<string | null>(null);
  const [loadError, setLoadError] = useState('');
  const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined;

  useEffect(() => {
    let disposed = false;

    async function mountWidget() {
      if (!siteKey) {
        setLoadError('Captcha site key is not configured');
        onTokenChange('');
        return;
      }

      try {
        await ensureTurnstileScript();
        if (disposed || !containerRef.current || !window.turnstile) {
          return;
        }

        widgetIdRef.current = window.turnstile.render(containerRef.current, {
          sitekey: siteKey,
          theme: 'dark',
          callback: (token: string) => onTokenChange(token),
          'expired-callback': () => onTokenChange(''),
          'error-callback': () => onTokenChange(''),
        });
      } catch (error) {
        if (!disposed) {
          const message = error instanceof Error ? error.message : 'Captcha failed to load';
          setLoadError(message);
          onTokenChange('');
        }
      }
    }

    mountWidget();

    return () => {
      disposed = true;
      if (widgetIdRef.current && window.turnstile) {
        window.turnstile.remove(widgetIdRef.current);
        widgetIdRef.current = null;
      }
    };
  }, [onTokenChange, siteKey]);

  if (loadError) {
    return <p className="text-sm text-red-400">{loadError}</p>;
  }

  return <div ref={containerRef} />;
}
