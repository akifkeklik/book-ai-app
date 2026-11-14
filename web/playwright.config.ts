import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end tests run against a hermetic stack: the Flask API serves the bundled catalog
 * with no Supabase configured, so nothing here can touch a real database.
 */
const BACKEND_PORT = 5055;
const WEB_PORT = 3055;
const API_KEY = 'e2e-local-api-key';

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://127.0.0.1:${WEB_PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
  webServer: [
    {
      command: 'python -u -m backend.app',
      cwd: '..',
      url: `http://127.0.0.1:${BACKEND_PORT}/api/health`,
      timeout: 120_000,
      reuseExistingServer: false,
      env: {
        PYTHONPATH: '.',
        HOST: '127.0.0.1',
        PORT: String(BACKEND_PORT),
        DEBUG: 'true',
        TESTING: 'true',
        SECRET_KEY: 'e2e-only-secret-key',
        LIBRIS_API_KEY: API_KEY,
        // Empty values win over backend/.env, keeping the run offline from Supabase and LLMs.
        SUPABASE_URL: '',
        SUPABASE_ANON_KEY: '',
        SUPABASE_DB_URL: '',
        DATABASE_URL: '',
        LLM_API_KEY: '',
      },
    },
    {
      command: `npm run build && npm run start -- -p ${WEB_PORT} -H 127.0.0.1`,
      url: `http://127.0.0.1:${WEB_PORT}`,
      timeout: 240_000,
      reuseExistingServer: false,
      env: {
        NEXT_DIST_DIR: '.next-e2e',
        BACKEND_URL: `http://127.0.0.1:${BACKEND_PORT}`,
        LIBRIS_API_KEY: API_KEY,
        NEXT_PUBLIC_SUPABASE_URL: 'https://e2e.supabase.invalid',
        NEXT_PUBLIC_SUPABASE_ANON_KEY: 'e2e-anon-key',
      },
    },
  ],
});
