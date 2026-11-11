# NX26: Next Football — Аудит исходного проекта (Этапы 1–2)

Дата: 2026-11-11. Файл: `NX26_Next_Football_Updated.rbxl` (421 061 байт, бинарный формат Roblox).
Скачан из этого репозитория через GitHub API, разобран собственным парсером (все 126 чанков, ошибок нет).

## Подтверждено по файлу (не по словам)

| Пункт | Заявлено | Факт |
|---|---|---|
| Instances | 739 | 739 |
| Скрипты | 24 | 24 (22 ModuleScript + 1 Script + 1 LocalScript) |
| MeshPart | 357 | 357 |
| SurfaceAppearance | 349 | 349 |
| Tottenham | есть | Model Workspace.Tottenham, 357 MeshPart |
| SoccerShared | 5 модулей | Config, FeintDefs, Remotes, Util, AnimationIds |
| SoccerServer | Main + 9 | все на месте |
| SoccerClient | ClientMain + 8 | все на месте |

## Стадион — настоящие ассеты
MeshId выборочно проверены через Roblox Economy API: реальные RenderMesh (AssetTypeId 4),
загружены 2024-09-03 пользователем dahsvsgss (id 798201246). Выдуманные контрольные ID дают 404.
Вывод: стадион — настоящая импортированная модель, пересоздавать нельзя.
Габариты: X ~ [-1119,1124], Y ~ [-17,373], Z ~ [-1244,1293] studs. Поле Config: 243x375, центр (0,0,0).

## Особенности файла
- Все чанки НЕ сжаты, Source хранится как String. Файл записан сторонним инструментом, формат корректный.
- Нет Lighting, StarterGui, SoundService, Teams, SpawnLocation, камеры — Studio создаёт их при открытии.
- Мяч, ворота, разметка строятся скриптами при запуске (FieldService/BallService).

## Качество кода (прочитаны все 24 скрипта, ~5600 строк)
Сохраняем без переписывания:
- BallService: свободный физический мяч, серверный network owner, ничего не приваривается;
  HasBall — производное; единственное удержание — ловля GK в своей штрафной; PlaceAt() полный сброс.
- ActionService: удары Normal/Finesse/Trivela/Knuckle/Header, пасы Normal/Through/Lob, LONG,
  подкаты Fast/Slide; серверная зарядка, кламп прицела, стамина, кулдауны, token-bucket.
- FeintService+FeintDefs: 21 финт, data-driven, без кулдаунов, комбо, окна уклонения, обман защитников.
- RulesService: голы/ауты только сервером в локальных координатах поля.
- MatchService: полный цикл матча, статистика. StaminaService: стамина + анти-телепорт.
- AnimationIds: пустые слоты, нормализация, левые варианты, приоритеты.
- Клиент: HUD, круглые кнопки (4 режима), клавиатура/геймпад/тач, свой shift-lock, анимации.

## Чего нет относительно ТЗ (будет добавлено)
1. Главное меню (KICK OFF / ULTIMATE TEAM / CAREER / CLUBS / SETTINGS).
2. Флоу Kick Off: Menu -> Team Selection -> Match Setup -> Match -> Results -> Menu.
3. 8 оригинальных NX-клубов с формами (сейчас RED/BLUE).
4. Расстановки 5v5 / 11v11 с именованными позициями.
5. ИИ-вратари (сейчас GK только реальный игрок).
6. 7 финтов из ТЗ отсутствуют: Lateral Heel-to-Heel, Sombrero Flick, Stop and Go, Scoop Turn,
   V-Cut, Berba Spin, Advanced Body Feint (есть 7 других бонусных).
7. SoundIds / звуки. 8. Настройки + DataStore. 9. Реестр стадионов.
10. Запрет смены команды/роли в матче. 11. SpawnLocation (создаётся сервером в лобби).
12. TEST_MODE=true — для публикации поставить false.

## Решения по рискам
- Стадион сохраняется побайтово: итоговый .rbxl собирается хирургией бинарника
  (замена Source + новые скрипты новыми INST/PROP/PRNT чанками). Геометрия/меши/текстуры не трогаются.
- Новые сервисы интегрируются через публичные API существующих, без переписывания ядра.
- ИИ-вратарь = серверная сущность-псевдоигрок, совместимая с BallService/TeamService. Полевых ботов нет.
