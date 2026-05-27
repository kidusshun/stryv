/// <reference types="vite/client" />

import type { StryvApi } from '../electron/preload';

declare global {
  interface Window {
    stryv?: StryvApi;
  }
}
