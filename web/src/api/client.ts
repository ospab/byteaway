import axios from 'axios';

// Default to proxying through nginx on /api/v1; override with VITE_MASTER_NODE_URL if provided.
const api = axios.create({
  baseURL: import.meta.env.VITE_MASTER_NODE_URL || '/api/v1'
});

export function extractApiErrorMessage(error: unknown, fallback: string): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data;
    if (typeof data === 'string' && data.trim().length > 0) {
      return data.trim();
    }
    if (data && typeof data === 'object') {
      const maybeMessage =
        (data as { error?: unknown; message?: unknown; detail?: unknown }).error ??
        (data as { error?: unknown; message?: unknown; detail?: unknown }).message ??
        (data as { error?: unknown; message?: unknown; detail?: unknown }).detail;
      if (typeof maybeMessage === 'string' && maybeMessage.trim().length > 0) {
        return maybeMessage.trim();
      }
    }
  }
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return fallback;
}

export type BalanceResponse = {
  client_id: string;
  balance_usd: number;
};

export type ProxyCredential = {
  credential_id: string;
  label?: string | null;
  username: string;
  created_at: string;
  traffic_limit_gb?: number | null;
};

export type CreateCredentialPayload = {
  label?: string;
  traffic_limit_gb?: number;
  allowed_ips?: string[];
  allowed_domains?: string[];
  country?: string;
};

export type BusinessAuthResponse = {
  session_token: string;
  expires_at: string;
  client_id: string;
  email: string;
  company_name: string;
};

export type BusinessToken = {
  credential_id: string;
  username: string;
  created_at: string;
  label?: string | null;
};

export type CreateBusinessTokenResponse = {
  credential_id: string;
  token: string;
  username: string;
  proxy_host: string;
  proxy_port: number;
  created_at: string;
  label?: string | null;
};

export async function registerBusiness(payload: {
  company_name: string;
  email: string;
  password: string;
  captcha_token: string;
}): Promise<BusinessAuthResponse> {
  const res = await api.post<BusinessAuthResponse>('/auth/business/register', payload);
  return res.data;
}

export async function loginBusiness(payload: {
  email: string;
  password: string;
  captcha_token: string;
}): Promise<BusinessAuthResponse> {
  const res = await api.post<BusinessAuthResponse>('/auth/business/login', payload);
  return res.data;
}

export async function createBusinessToken(
  sessionToken: string,
  payload: { label?: string; country?: string }
): Promise<CreateBusinessTokenResponse> {
  const res = await api.post<CreateBusinessTokenResponse>('/auth/business/tokens', payload, {
    headers: { Authorization: `Bearer ${sessionToken}` }
  });
  return res.data;
}

export async function listBusinessTokens(sessionToken: string): Promise<BusinessToken[]> {
  const res = await api.get<{ tokens: BusinessToken[] }>('/auth/business/tokens', {
    headers: { Authorization: `Bearer ${sessionToken}` }
  });
  return res.data.tokens;
}

export async function revokeBusinessToken(sessionToken: string, credentialId: string): Promise<void> {
  await api.delete(`/auth/business/tokens/${credentialId}`, {
    headers: { Authorization: `Bearer ${sessionToken}` }
  });
}

export async function createDownloadTicket(captchaToken: string): Promise<{ download_url: string; expires_in_seconds: number }> {
  const res = await api.post<{ download_url: string; expires_in_seconds: number }>('/public/downloads/ticket', {
    captcha_token: captchaToken,
  });
  return res.data;
}

export async function fetchBalance(token: string): Promise<BalanceResponse> {
  const res = await api.get<BalanceResponse>('/balance', {
    headers: { Authorization: `Bearer ${token}` }
  });
  return res.data;
}

export async function listCredentials(token: string): Promise<ProxyCredential[]> {
  const res = await api.get<{ credentials: ProxyCredential[] }>('/business/proxy-credentials', {
    headers: { Authorization: `Bearer ${token}` }
  });
  return res.data.credentials;
}

export async function createCredential(token: string, payload: CreateCredentialPayload) {
  const res = await api.post(
    '/business/proxy-credentials',
    payload,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  return res.data as { credential_id: string; username: string; password: string; proxy_host: string; proxy_port: number };
}
