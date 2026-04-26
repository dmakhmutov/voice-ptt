# VoicePTT

Push-to-talk транскрипция для macOS. Хоткей → запись с микрофона → текст в активное окно.

Стек: Swift + [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT v3 на Apple Neural Engine). Поддержка русского и английского.

## Сборка

```sh
./build.sh
open VoicePTT.app
```

При первом запуске:
1. macOS попросит разрешение на микрофон → разрешить.
2. Чтобы автопейст работал, дай приложению **Accessibility**: System Settings → Privacy & Security → Accessibility → добавить VoicePTT.app.
3. Модель Parakeet (~2.5 GB) скачается при первом запуске — терпеливо ждём, прогресс в логах.

## Использование

- Хоткей по умолчанию: `⌘⇧Space` (Cmd+Shift+Space).
- Режим по умолчанию: **toggle** (нажал — пишет, нажал ещё раз — стоп и транскрипция).
- Альтернативный режим: **hold** (зажал — пишет, отпустил — транскрипция).

Настройки в менюбаре: иконка микрофона → Settings…

## Разработка

```sh
swift build           # компиляция
swift run VoicePTT    # запуск без .app-обёртки (без LSUIElement, иконка в Dock)
```
