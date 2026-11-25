/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { getWebHelloMessage } from './appMeta';

/**
 * Componente raíz del entorno web.
 * Tal como solicitó el usuario, la compilación web muestra únicamente un "Hello World"
 * mientras que la aplicación móvil completa de Aura Music (Flutter + Dart + ExoPlayer)
 * se encuentra organizada de forma modular en `/aura_music`.
 */
export default function App() {
  return (
    <main className="min-h-screen bg-[#F9F6F0] text-[#2C2524] flex items-center justify-center p-6">
      <h1 className="text-3xl font-semibold tracking-tight">{getWebHelloMessage()}</h1>
    </main>
  );
}
