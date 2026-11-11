# NX26 — План интеграции (Этап 3)

Принцип: минимально рискованные правки. Стадион и ядро (BallService, RulesService, FeintService,
ActionService, StaminaService) сохраняются; расширяются только точки интеграции.

## Новые общие модули (ReplicatedStorage/SoccerShared)
- Clubs.lua — 8 NX-клубов: имя, цвета, Home/Away форма (пустой template = одежду аватара НЕ трогаем), цвета UI.
- Formations.lua — 5v5 (3 схемы) и 11v11 (4 схемы), именованные слоты, расширяемо.
- Stadiums.lua — Tottenham (enabled) + NX Arena (COMING SOON, заблокирован).
- SoundIds.lua — пустые слоты звуков + нормализация.
- SettingsDefs.lua — дефолты настроек + валидация.
- FeintDefs.lua — +7 финтов (итого 28, все 21 из ТЗ).
- AnimationIds.lua — +слоты новых финтов и GK (Save/Parry/Punt).
- Remotes.lua — +MatchControl, +SettingsSync.
- Config.lua — новые секции (GK AI, лобби, меню).

## Сервер
- TeamService: клубы сторон, позиции, формы (только если template задан), запрет смены в матче, ИИ-сущности.
- MatchService: управление из меню (Lobby->Setup->Match->Results->Lobby), расстановка, лог голов, длительность.
- MatchControlService (новый): валидация setup, хост, запуск/завершение.
- GoalkeeperService: +ИИ-вратари (по 1 на команду, отключаются при реальном GK, без телепортов к мячу).
- BallService: минимальная правка — учёт ИИ-вратарей в stepKeeperCatch.
- SettingsService (новый): DataStore с защитой. LobbyService (новый): SpawnLocation в лобби.
- SoundRunner (новый): серверные звуки событий. Main: подключение новых сервисов.

## Клиент
- MainMenu (новый): 5 кнопок, COMING SOON блокировки, анимации, hover, тач, геймпад, адаптив.
- KickOffFlow (новый): выбор клубов, предпросмотр формы, настройка матча, START MATCH, результаты -> CONTINUE.
- SettingsMenu (новый): громкость/камера/чувствительность/ребинд/графика.
- MenuCamera (новый): кинематографичная камера в меню. SoundController (новый): UI + события.
- ClientMain: меню -> матч -> меню. HudController: результаты с авторами голов и CONTINUE.
- InputController: хоткеи финтов 16-28, ребинд. ActionBar: прокручиваемый док финтов на телефонах.

## Сборка (Этапы 8-10)
- Статическая проверка синтаксиса всех Lua (парсер Lua 5.1; новый код без Luau-only синтаксиса).
- Сборка NX26_Next_Football_v2.rbxl хирургией бинарника, стадион побайтово сохранён.
- Повторный парсинг итогового файла (739+N instances, все скрипты на месте).
- ZIP исходников + отчёт + инструкция. Всё коммитится в репозиторий.

## Части
Часть 1: аудит + план + оригиналы в git. Часть 2: общие модули. Часть 3: сервер.
Часть 4: клиент. Часть 5: сборка .rbxl + проверки + финальный отчёт.
